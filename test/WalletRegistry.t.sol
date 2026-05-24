// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {WalletRegistry} from "../src/WalletRegistry.sol";

contract WalletRegistryTest is Test {
    /////////////////
    //  Contracts  //
    /////////////////

    WalletRegistry registry;

    /////////////////
    //  Test user  //
    /////////////////

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    ///////////////////
    //  Constants    //
    ///////////////////

    string constant VALID_USERNAME = "sanskar";
    string constant VALID_USERNAME_2 = "Dante";
    string constant LONG_USERNAME = "thisusernameiswaytoolongtobeallowed123";
    string constant EMPTY_USERNAME = "";
    string constant MAX_USERNAME = "abcdefghijklmnopqrstuvwxyz123456"; // 32 characters
    bytes32 constant VALID_PIN_HASH = keccak256(abi.encodePacked("12345"));
    bytes32 constant WRONG_PIN_HASH = keccak256(abi.encodePacked("99999"));

    //////////////
    //  Events  //
    //////////////

    event WalletRegistered(address indexed wallet, string userName, uint256 timeStamp);
    event WalletRemoved(address indexed wallet, uint256 timeStamp);
    event UserNameUpdated(address indexed wallet, string oldUserName, string newUserName);

    //////////////
    //  setup   //
    //////////////

    function setUp() public {
        vm.prank(owner);
        registry = new WalletRegistry();
    }

    ////////////////////////////////
    //  registerWallet Tests      //
    ////////////////////////////////

    function test_RegisterWallet_Success() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        assertTrue(registry.isWalletRegistered(user1));
        assertEq(registry.getTotalRegistered(), 1);
    }

    function test_RegisterWallet_ProfileDataCorrect() public {
        vm.warp(1000); // Set block timestamp to 1000
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        WalletRegistry.UserProfile memory profile = registry.getUserProfile(user1);
        assertEq(profile.walletAddress, user1);
        assertEq(profile.userName, VALID_USERNAME);
        assertTrue(profile.isActive);
        assertEq(profile.registeredAt, 1000);
        assertEq(profile.latestUpdate, 1000);
    }

    function test_RegisterWallet_EmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit WalletRegistered(user1, VALID_USERNAME, block.timestamp);
        registry.registerWallet(VALID_USERNAME);
    }

    function test_RegisterWallet_MultipleUsers() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user2);
        registry.registerWallet(VALID_USERNAME_2);

        vm.prank(user3);
        registry.registerWallet("user3");

        assertEq(registry.getTotalRegistered(), 3);
        assertTrue(registry.isWalletRegistered(user1));
        assertTrue(registry.isWalletRegistered(user2));
        assertTrue(registry.isWalletRegistered(user3));
    }

    function test_RegisterWallet_MaxUsernameAllowed() public {
        vm.prank(user1);
        registry.registerWallet(MAX_USERNAME);

        assertTrue(registry.isWalletRegistered(user1));
    }

    function test_RegisterWallet_Revert_AlreadyRegistered() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(WalletRegistry.WalletRegistry__AlreadyRegistered.selector, user1));
        registry.registerWallet(VALID_USERNAME);
    }

    function test_RegisterWallet_Revert_EmptyUsername() public {
        vm.prank(user1);
        vm.expectRevert(WalletRegistry.WalletRegistry__EmptyUsername.selector);
        registry.registerWallet(EMPTY_USERNAME);
    }

    function test_RegisterWallet_Revert_UsernameTooLong() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                WalletRegistry.WalletRegistry__UsernameTooLong.selector, bytes(LONG_USERNAME).length, 32
            )
        );
        registry.registerWallet(LONG_USERNAME);
    }

    function test_UpdateUsername_Revert_WhenPaused() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(owner);
        registry.pauseContract();

        vm.prank(user1);
        vm.expectRevert();
        registry.updateUserName(VALID_USERNAME_2);
    }

    ////////////////////////////////
    //  Pause / Unpause Tests     //
    ////////////////////////////////

    function test_Pause_Success() public {
        vm.prank(owner);
        registry.pauseContract();

        assertTrue(registry.isContractPaused());
    }

    function test_Unpause_Success() public {
        vm.prank(owner);
        registry.pauseContract();

        vm.prank(owner);
        registry.unpauseContract();

        assertFalse(registry.isContractPaused());
    }

    function test_Pause_Revert_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.pauseContract();
    }

    function test_Unpause_WorksAfterUnpause() public {
        vm.prank(owner);
        registry.pauseContract();

        vm.prank(owner);
        registry.unpauseContract();

        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        assertTrue(registry.isWalletRegistered(user1));
    }

    ////////////////////////////////
    //  View Functions Tests      //
    ////////////////////////////////

    function test_GetUserProfile_Revert_NotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(WalletRegistry.WalletRegistry__NotRegistered.selector, user1));
        registry.getUserProfile(user1);
    }

    function test_IsWalletRegistered_ReturnsFalse() public view {
        assertFalse(registry.isWalletRegistered(user1));
    }

    function test_GetTotalRegistered_StartsAtZero() public view {
        assertEq(registry.getTotalRegistered(), 0);
    }

    ////////////////////////////////
    //  Fuzz Tests                //
    ////////////////////////////////

    function testFuzz_RegisterWallet_ValidUsername(string memory userName) public {
        vm.assume(bytes(userName).length > 0);
        vm.assume(bytes(userName).length <= 32);

        vm.prank(user1);
        registry.registerWallet(userName);
        assertTrue(registry.isWalletRegistered(user1));
    }

    function testFuzz_RegisterWallet_Revert_LongUsername(string memory UserName) public {
        vm.assume(bytes(UserName).length > 32);

        vm.prank(user1);
        vm.expectRevert();
        registry.registerWallet(UserName);
    }

    ////////////////////////////////
    //  removeWallet Tests        //
    ////////////////////////////////

    function test_RemoveWallet_Success() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.removeWallet();

        assertFalse(registry.isWalletRegistered(user1));
        assertEq(registry.getTotalRegistered(), 0);
    }

    function test_RemoveWallet_TotalCountDecreases() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user2);
        registry.registerWallet(VALID_USERNAME_2);

        vm.prank(user1);
        registry.removeWallet();

        assertEq(registry.getTotalRegistered(), 1);
    }

    function test_RemoveWallet_EmitsEvent() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit WalletRemoved(user1, block.timestamp);
        registry.removeWallet();
    }

    function test_RemoveWallet_Revert_NotRegistered() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(WalletRegistry.WalletRegistry__NotRegistered.selector, user1));
        registry.removeWallet();
    }

    function test_RemoveWallet_Revert_WhenPaused() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(owner);
        registry.pauseContract();

        vm.prank(user1);
        vm.expectRevert();
        registry.removeWallet();
    }

    function test_RemoveWallet_CanRegisterAgain() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.removeWallet();

        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        assertTrue(registry.isWalletRegistered(user1));
    }

    ////////////////////////////////
    //  updateUserName Tests      //
    ////////////////////////////////

    function test_UpdateUsername_Success() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.updateUserName(VALID_USERNAME_2);

        WalletRegistry.UserProfile memory profile = registry.getUserProfile(user1);
        assertEq(profile.userName, VALID_USERNAME_2);
    }

    function test_UpdateUsername_TimestampUpdated() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.warp(2000);
        vm.prank(user1);
        registry.updateUserName(VALID_USERNAME_2);

        WalletRegistry.UserProfile memory profile = registry.getUserProfile(user1);
        assertEq(profile.latestUpdate, 2000);
    }

    function test_UpdateUsername_EmitsEvent() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit UserNameUpdated(user1, VALID_USERNAME, VALID_USERNAME_2);
        registry.updateUserName(VALID_USERNAME_2);
    }

    function test_UpdateUsername_Revert_EmptyUsername() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        vm.expectRevert(WalletRegistry.WalletRegistry__EmptyUsername.selector);
        registry.updateUserName(EMPTY_USERNAME);
    }

    function test_UpdateUsername_Revert_TooLong() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                WalletRegistry.WalletRegistry__UsernameTooLong.selector, bytes(LONG_USERNAME).length, 32
            )
        );
        registry.updateUserName(LONG_USERNAME);
    }

    ////////////////////////////////
    //  setPin Tests              //
    ////////////////////////////////

    function test_SetPin_Success() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.setPin(VALID_PIN_HASH);

        assertTrue(registry.hasPinSet(user1));
    }

    function test_SetPin_VerifyPin_Correct() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.setPin(VALID_PIN_HASH);

        vm.prank(user1);
        assertTrue(registry.verifyPin(VALID_PIN_HASH));
    }

    function test_SetPin_VerifyPin_WrongPin() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.setPin(VALID_PIN_HASH);

        vm.prank(user1);
        assertFalse(registry.verifyPin(WRONG_PIN_HASH));
    }

    function test_SetPin_Revert_NotRegistered() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(WalletRegistry.WalletRegistry__NotRegistered.selector, user1));
        registry.setPin(VALID_PIN_HASH);
    }

    function test_SetPin_Revert_AlreadySet() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.setPin(VALID_PIN_HASH);

        vm.prank(user1);
        vm.expectRevert(bytes("PIN already set"));
        registry.setPin(VALID_PIN_HASH);
    }

    function test_SetPin_Revert_WhenPaused() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(owner);
        registry.pauseContract();

        vm.prank(user1);
        vm.expectRevert();
        registry.setPin(VALID_PIN_HASH);
    }

    function test_SetPin_MultipleUsers_Independent() public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);
        vm.prank(user1);
        registry.setPin(VALID_PIN_HASH);

        vm.prank(user2);
        registry.registerWallet(VALID_USERNAME_2);
        vm.prank(user2);
        registry.setPin(WRONG_PIN_HASH);

        vm.prank(user1);
        assertTrue(registry.verifyPin(VALID_PIN_HASH));

        vm.prank(user2);
        assertTrue(registry.verifyPin(WRONG_PIN_HASH));

        vm.prank(user1);
        assertFalse(registry.verifyPin(WRONG_PIN_HASH));
    }

    ////////////////////////////////
    //  setPin Fuzz Tests         //
    ////////////////////////////////

    function testFuzz_SetPin_AnyHash(bytes32 randomPin) public {
        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.setPin(randomPin);

        vm.prank(user1);
        assertTrue(registry.verifyPin(randomPin));
    }

    function testFuzz_SetPin_WrongHash(bytes32 correctPin, bytes32 wrongPin) public {
        vm.assume(correctPin != wrongPin);

        vm.prank(user1);
        registry.registerWallet(VALID_USERNAME);

        vm.prank(user1);
        registry.setPin(correctPin);

        vm.prank(user1);
        assertFalse(registry.verifyPin(wrongPin));
    }
}
