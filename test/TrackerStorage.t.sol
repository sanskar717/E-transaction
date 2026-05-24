// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TrackerStorage} from "../src/TrackerStorage.sol";
import {WalletRegistry} from "../src/WalletRegistry.sol";

contract MockV3Aggregator {
    uint8 public decimals;
    int256 public latestAnswer;
    uint80 public lastestRound;
    uint256 public latestTimestamp;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        latestAnswer = _initialAnswer;
        lastestRound = 1;
        latestTimestamp = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updateAt, uint80 answeredInRound)
    {
        return (lastestRound, latestAnswer, latestTimestamp, latestTimestamp, lastestRound);
    }

    function description() external pure returns (string memory) {
        return "ETH / USD";
    }

    function updateAnswer(int256 _newAnswer) external {
        latestAnswer = _newAnswer;
        lastestRound++;
        latestTimestamp = block.timestamp;
    }
}

contract TrackerStorageTest is Test {
    /////////////////
    //  Contracts  //
    /////////////////

    TrackerStorage trackerStorage;
    WalletRegistry registry;
    MockV3Aggregator mockPriceFeed;

    /////////////////
    //  Test Users //
    /////////////////

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address unregistered = makeAddr("unregistered ");
    address authorizedTracker = makeAddr("authorizedTracker");

    ///////////////////
    //  Constants    //
    ///////////////////

    int256 constant ETH_USD_PRICE = 2000e8; // Mock price feed returns 8 decimals|| $2000 per ETH (8 decimals)
    uint256 constant SEND_AMOUNT = 1 ether;
    uint256 constant GAS_USED = 21000;
    uint256 constant GAS_PRICE = 20 gwei;

    //////////////
    //  Events  //
    //////////////

    event txRecorded(
        address indexed wallet,
        uint256 amountInWei,
        uint256 amountInUsd,
        uint256 gasFeeInWei,
        uint256 gasFeeInUsd,
        uint8 month,
        uint16 year,
        bool isSent,
        uint256 timeStamp
    );

    event monthlyStatsUpdated(
        address indexed wallet, uint8 month, uint16 year, uint256 totaltx, uint256 totalGasFeeUsd
    );

    event AuthorizedTrackerSet(address indexed tracker);

    //////////////
    //  Setup   //
    //////////////

    function setUp() public {
        vm.warp(1735689600);

        mockPriceFeed = new MockV3Aggregator(8, ETH_USD_PRICE);

        vm.prank(owner);
        registry = new WalletRegistry();

        vm.prank(owner);
        trackerStorage = new TrackerStorage(address(mockPriceFeed), address(registry));

        vm.prank(owner);
        trackerStorage.setAuthorizedTracker(authorizedTracker);

        vm.prank(user1);
        registry.registerWallet("user1");

        vm.prank(user2);
        registry.registerWallet("user2");

        vm.warp(block.timestamp);
    }

    ////////////////////////////////
    //  Helper Functions          //
    ////////////////////////////////

    function _getCurrentMonth() internal view returns (uint8) {
        uint256 SECONDS_PER_DAY = 86400;
        uint256 SECONDS_PER_YEAR = SECONDS_PER_DAY * 365;
        uint256 dayOfYear = (block.timestamp % SECONDS_PER_YEAR) / SECONDS_PER_DAY;

        if (dayOfYear < 31) return 1;
        else if (dayOfYear < 59) return 2;
        else if (dayOfYear < 90) return 3;
        else if (dayOfYear < 120) return 4;
        else if (dayOfYear < 151) return 5;
        else if (dayOfYear < 181) return 6;
        else if (dayOfYear < 212) return 7;
        else if (dayOfYear < 243) return 8;
        else if (dayOfYear < 273) return 9;
        else if (dayOfYear < 304) return 10;
        else if (dayOfYear < 334) return 11;
        else return 12;
    }

    function _getCurrentYear() internal view returns (uint16) {
        uint256 SECONDS_PER_YEAR = 86400 * 365;
        return uint16(1970 + block.timestamp / SECONDS_PER_YEAR);
    }

    ////////////////////////////////
    //  Constructor Tests         //
    ////////////////////////////////

    function test_Constructor_PriceFeedSet() public view {
        assertEq(trackerStorage.getPriceFeed(), address(mockPriceFeed));
    }

    function test_Constructor_Revert_ZeroPriceFeed() public {
        vm.expectRevert(TrackerStorage.TrackerStorage__ZeroAddress.selector);
        new TrackerStorage(address(0), address(registry));
    }

    function test_Constructor_Revert_ZeroRegistry() public {
        vm.expectRevert(TrackerStorage.TrackerStorage__ZeroAddress.selector);
        new TrackerStorage(address(mockPriceFeed), address(0));
    }

    ////////////////////////////////
    //  setAuthorizedTracker      //
    ////////////////////////////////

    function test_SetAuthorizedTracker_Success() public {
        vm.prank(owner);
        trackerStorage.setAuthorizedTracker(authorizedTracker);

        assertEq(trackerStorage.getAuthorizedTracker(), authorizedTracker);
    }

    function test_SetAuthorizedTracker_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false); // checkTopic1, checkTopic2, checkTopic3, checkData
        emit AuthorizedTrackerSet(authorizedTracker);
        trackerStorage.setAuthorizedTracker(authorizedTracker);
    }

    function test_SetAuthorizedTracker_Revert_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        trackerStorage.setAuthorizedTracker(authorizedTracker);
    }

    function test_SetAuthorizedTracker_Revert_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TrackerStorage.TrackerStorage__ZeroAddress.selector);
        trackerStorage.setAuthorizedTracker(address(0));
    }

    ////////////////////////////////
    //  recordTransaction Tests   //
    ////////////////////////////////

    function test_RecordTransaction_Success_Sent() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);

        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);
        assertEq(txs.length, 1);
        assertEq(txs[0].amountWei, SEND_AMOUNT);
        assertTrue(txs[0].isSent);
    }

    function test_RecordTransaction_Success_Received() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, false);

        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);
        assertEq(txs.length, 1);
        assertFalse(txs[0].isSent);
    }

    function test_RecordTransaction_UsdAmountCorrect() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);

        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);
        assertEq(txs[0].amountUsd, 2000e18);
    }

    function test_RecordTransaction_GasFeeCorrect() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);

        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);
        uint256 expectedGasFeeWei = GAS_USED * GAS_PRICE;
        assertEq(txs[0].gasFeeWei, expectedGasFeeWei);
    }

    function test_RecordTransaction_MonthlyStatsUpdated() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);

        uint8 month = _getCurrentMonth();
        uint16 year = _getCurrentYear();

        TrackerStorage.MonthlyStats memory stats = trackerStorage.getMonthlyStats(user1, month, year);

        assertEq(stats.totalTransactions, 1);
        assertEq(stats.totalEthSentWei, SEND_AMOUNT);
    }

    function test_RecordTransaction_LifetimeStatsUpdated() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);

        (uint256 totaltx, uint256 ethSentWei,,,,,) = trackerStorage.getLifetimeStats(user1);
        assertEq(totaltx, 1);
        assertEq(ethSentWei, SEND_AMOUNT);
    }

    function test_RecordTransaction_EmitsEvent() public {
        vm.prank(authorizedTracker);
        vm.expectEmit(true, false, false, false);
        emit txRecorded(
            user1,
            SEND_AMOUNT,
            2000e18,
            GAS_USED * GAS_PRICE,
            0,
            _getCurrentMonth(),
            _getCurrentYear(),
            true,
            block.timestamp
        );
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);
    }

    function test_RecordTransaction_Revert_NotAuthorized() public {
        vm.prank(user1);
        vm.expectRevert(TrackerStorage.TrackerStorage__NotAuthorized.selector);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);
    }

    function test_RecordTransaction_Revert_NotRegistered() public {
        vm.prank(authorizedTracker);
        vm.expectRevert(TrackerStorage.TrackerStorage__NotRegistered.selector);
        trackerStorage.recordTransaction(unregistered, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, true);
    }

    ////////////////////////////////
    //  MockV3Aggregator Tests    //
    ////////////////////////////////

    function test_MockPriceFeed_Description() public view {
        string memory desc = mockPriceFeed.description();
        assertEq(desc, "ETH / USD");
    }

    ////////////////////////////////
    //  getMonthlyStats Tests     //
    ////////////////////////////////

    function test_GetMonthlyStats_Revert_InvalidMonth() public {
        vm.expectRevert(TrackerStorage.TrackerStorage__InvalidMonth.selector);
        trackerStorage.getMonthlyStats(user1, 19, 2022);
    }

    function test_GetMonthlyStats_Revert_ZeroMonth() public {
        vm.expectRevert(TrackerStorage.TrackerStorage__InvalidMonth.selector);
        trackerStorage.getMonthlyStats(user1, 0, 2022);
    }

    function test_GetMonthlyStats_Revert_InvalidYear() public {
        vm.expectRevert(TrackerStorage.TrackerStorage__InvalidYear.selector);
        trackerStorage.getMonthlyStats(user1, 1, 1969);
    }

    function test_GetMonthlyStats_EmptyForFreshWallet() public view {
        TrackerStorage.MonthlyStats memory stats = trackerStorage.getMonthlyStats(user1, 1, 2025);

        assertEq(stats.totalTransactions, 0);
        assertEq(stats.totalEthSentWei, 0);
        assertEq(stats.totalGasFeeWei, 0);
    }

    ////////////////////////////////
    //  getLifetimeStats Tests    //
    ////////////////////////////////

    function test_GetLifetimeStats_MultipleTransactions() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, 1 ether, GAS_USED, GAS_PRICE, true);

        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, 2 ether, GAS_USED, GAS_PRICE, true);

        (uint256 totaltx, uint256 ethSentWei,,,,,) = trackerStorage.getLifetimeStats(user1);

        assertEq(totaltx, 2);
        assertEq(ethSentWei, 3 ether);
    }

    function test_GetLifetimeStats_ReceivedTracked() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, GAS_PRICE, false);

        (uint256 totaltx, uint256 ethSentWei,,,,,) = trackerStorage.getLifetimeStats(user1);

        assertEq(totaltx, 1);
        assertEq(ethSentWei, 0);
    }

    function test_GetLifetimeStats_ZeroForFreshWallet() public view {
        (uint256 totaltx, uint256 ethSentWei, uint256 ethReceivedWei, uint256 gasFees,,,) =
            trackerStorage.getLifetimeStats(user1);

        assertEq(totaltx, 0);
        assertEq(ethSentWei, 0);
        assertEq(ethReceivedWei, 0);
        assertEq(gasFees, 0);
    }

    ////////////////////////////////
    //  getCurrentEthPrice Tests  //
    ////////////////////////////////

    function test_GetCurrentEthPrice_ReturnsCorrectPrice() public view {
        uint256 price = trackerStorage.getCurrentEthPrice();

        assertEq(price, 2000e18);
    }

    function test_GetCurrentEthPrice_UpdatesWithFeed() public {
        mockPriceFeed.updateAnswer(3000e8);

        uint256 price = trackerStorage.getCurrentEthPrice();
        assertEq(price, 3000e18);
    }

    ////////////////////////////////
    //  getAllTransactions Tests  //
    ////////////////////////////////

    function test_GetAllTransactions_ReturnsAll() public {
        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, 1 ether, GAS_USED, GAS_PRICE, true);

        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, 2 ether, GAS_USED, GAS_PRICE, false);

        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);

        assertEq(txs.length, 2);
        assertEq(txs[0].amountWei, 1 ether);
        assertEq(txs[1].amountWei, 2 ether);
    }

    function test_GetAllTransactions_EmptyForFreshWallet() public view {
        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);

        assertEq(txs.length, 0);
    }

    ////////////////////////////////
    //  Fuzz Tests                //
    ////////////////////////////////

    function testFuzz_RecordTransaction_AnyValidAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1000000 ether);

        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, amount, GAS_USED, GAS_PRICE, true);

        (uint256 totaltx, uint256 ethSentWei,,,,,) = trackerStorage.getLifetimeStats(user1);

        assertEq(totaltx, 1);
        assertEq(ethSentWei, amount);
    }

    function testFuzz_RecordTransaction_AnyGasPrice(uint256 gasPrice) public {
        vm.assume(gasPrice > 0 && gasPrice < 1000 gwei);

        vm.prank(authorizedTracker);
        trackerStorage.recordTransaction(user1, user2, SEND_AMOUNT, GAS_USED, gasPrice, true);

        TrackerStorage.TxRecord[] memory txs = trackerStorage.getAllTransactions(user1);
        assertEq(txs[0].gasPrice, gasPrice);
        assertEq(txs[0].gasFeeWei, GAS_USED * gasPrice);
    }
}
