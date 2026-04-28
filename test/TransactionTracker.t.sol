// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TransactionTracker} from "../src/TransactionTracker.sol";
import {WalletRegistry} from "../src/WalletRegistry.sol";

contract TransactionTrackerTest is Test {
    /////////////////
    //  Contracts  //
    /////////////////

    TransactionTracker tracker;
    WalletRegistry registry;

    /////////////////
    //  Test user  //
    /////////////////
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address unregistered = makeAddr("unregistered");

    ///////////////////
    //  Constants    //
    ///////////////////

    uint256 constant SEND_AMOUNT = 1 ether;
    uint256 constant GAS_PRICE = 20 gwei;
    uint256 constant GAS_LIMIT = 21000;
    uint256 constant STARTING_BALANCE = 10 ether;

    //////////////
    //  Events  //
    //////////////

     event ethSent(
        address indexed from, address indexed to, uint256 amount, uint256 gasPrice, uint256 gasLimit, uint256 timeStamp
    );
    event ethReceived(
        address indexed from, address indexed to, uint256 amount, uint256 gasPrice, uint256 gasLimit, uint256 timeStamp
    );

    //////////////
    //  setup   //
    //////////////

    function setUp() public {
        vm.prank(owner);
        registry = new WalletRegistry();

        vm.prank(owner);
        tracker = new TransactionTracker(address(registry));

        vm.deal(user1, STARTING_BALANCE);
        vm.deal(user2, STARTING_BALANCE);
        vm.deal(user3, STARTING_BALANCE);

        vm.prank(user1);
        registry.registerWallet("user1");

        vm.prank(user2);
        registry.registerWallet("user2");
    }

    ////////////////////////////////
    //  Constructor Tests         //
    ////////////////////////////////

    function test_Constructor_RegistryAddressSet() public view {
        assertEq(tracker.getRegistryAddress(), address(registry));
    }

    ////////////////////////////////
    //  sendEth Tests             //
    ////////////////////////////////

    function test_SendEth_Success() public {
        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        assertEq(address(user2).balance, STARTING_BALANCE + SEND_AMOUNT);
    }

    function test_SendEth_SenderBalanceDecreases() public {
        uint256 balanceBefore = address(user1).balance;

        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        assertLt(address(user1).balance, balanceBefore);
    }

    function test_SendEth_TxCountIncreases() public {
        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        (uint256 totalTx,,) = tracker.getWalletStats(user1);
        assertEq(totalTx, 1);
    }

    function test_SendEth_MultipleTxCount() public {
        vm.prank(user1);
        tracker.sendEth{value: 0.5 ether}(payable(user2), GAS_PRICE, GAS_LIMIT);

        vm.prank(user1);
        tracker.sendEth{value: 0.7 ether}(payable(user2), GAS_PRICE, GAS_LIMIT);

        vm.prank(user1);
        tracker.sendEth{value: 0.2 ether}(payable(user2), GAS_PRICE, GAS_LIMIT);

        (uint256 totalTx,,) = tracker.getWalletStats(user1);
        assertEq(totalTx, 3);
    }

    function test_SendEth_TotalEthSentTracked() public {
        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        (, uint256 totalSent,) = tracker.getWalletStats(user1);
        assertEq(totalSent, SEND_AMOUNT);
    }

    function test_SendEth_ReceiverStatsUpdated_WhenRegistered() public {
        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        (uint256 totalTx,, uint256 totalReceived) = tracker.getWalletStats(user2);
        assertEq(totalTx, 1);
        assertEq(totalReceived, SEND_AMOUNT);
    }

    function test_SendEth_ReceiverStatsNotUpdated_WhenUnregistered() public {
        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(unregistered), GAS_PRICE, GAS_LIMIT);

        (uint256 totaltx,,) = tracker.getWalletStats(unregistered);
        assertEq(totaltx, 0);
    }

    function test_SendEth_EmitsEthSentEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ethSent(user1, user2, SEND_AMOUNT, GAS_PRICE, GAS_LIMIT, block.timestamp);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);
    }

    function test_SendEth_EmitsEthReceivedEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ethReceived(user1, user2, SEND_AMOUNT, GAS_PRICE, GAS_LIMIT, block.timestamp);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);
    }

    function test_SendEth_Revert_SenderNotRegistered() public {
        vm.prank(unregistered);
        vm.deal(unregistered, STARTING_BALANCE);
        vm.expectRevert(TransactionTracker.TransactionTracker__WalletNotRegistered.selector);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);
    }   

    function test_SendEth_Revert_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(TransactionTracker.TransactionTracker__ZeroAmount.selector);
        tracker.sendEth{value: 0} (payable(user2), GAS_PRICE, GAS_LIMIT);
    }

    function test_SendEth_Revert_SameAddress() public {
        vm.prank(user1);
        vm.expectRevert(TransactionTracker.TransactionTracker__SameAddress.selector);
        tracker.sendEth{value: SEND_AMOUNT} (payable(user1), GAS_PRICE, GAS_LIMIT);
    }

    function test_SendEth_Revert_WhenPaused() public {
        vm.prank(owner);
        tracker.pauseContract();

        vm.prank(user1);
        vm.expectRevert();

        tracker.sendEth{value: SEND_AMOUNT} (payable(user2), GAS_PRICE, GAS_LIMIT);
    }

    ////////////////////////////////
    //  getTransactions Tests     //
    ////////////////////////////////

    function test_GetTransactions_ReturnsCorrectData() public {
        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        TransactionTracker.Transaction[] memory txs = tracker.getTransactions(user1);

        assertEq(txs.length, 1);
        assertEq(txs[0].from, user1);
        assertEq(txs[0].to, user2);
        assertEq(txs[0].amount, SEND_AMOUNT);
        assertEq(txs[0].gasPrice, GAS_PRICE);
        assertEq(txs[0].gasLimit, GAS_LIMIT);
    } 

    function test_GetTransactions_EmptyIfNoTx() public view {
        TransactionTracker.Transaction[] memory  txs = tracker.getTransactions(user1);
        assertEq(txs.length, 0);
    }

    ////////////////////////////////
    //  getMonthlyTransactions    //
    ////////////////////////////////

    function test_GetMonthlyTransactions_FiltersByTime() public {
        uint256 monthStart = block.timestamp;
        uint256 monthEnd = block.timestamp + 30 days;

        vm.prank(user1);
        tracker.sendEth{value: SEND_AMOUNT}(payable(user2), GAS_PRICE, GAS_LIMIT);

        vm.warp(block.timestamp + 40 days);
        vm.prank(user1);
        tracker.sendEth{value: 0.5 ether}(payable(user2), GAS_PRICE, GAS_LIMIT);

        TransactionTracker.Transaction[] memory monthlyTxs = tracker.getMonthlyTransactions(user1, monthStart, monthEnd);

        assertEq(monthlyTxs.length, 1);
        assertEq(monthlyTxs[0].amount, SEND_AMOUNT);
    }

    function test_GetMonthlyTransactions_EmptyIfNoTxInRange() public view {
        uint256 monthStart = block.timestamp;
        uint256 monthEnd = block.timestamp + 30 days;

        TransactionTracker.Transaction[] memory monthlyTxs = tracker.getMonthlyTransactions(user1, monthStart, monthEnd);

        assertEq(monthlyTxs.length, 0);
    }
}
