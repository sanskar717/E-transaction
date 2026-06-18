// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PriceConverter} from "../src/PriceConverter.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator {
    uint8 public decimals;
    int256 public latestAnswer;
    uint80 public roundId;
    uint256 public updateAt;
    uint80 public answeredInRound;
    string public _description;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        latestAnswer = _initialAnswer;
        roundId = 1;
        updateAt = block.timestamp;
        answeredInRound = 1;
        _description = "ETH / USD";
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, latestAnswer, block.timestamp, updateAt, answeredInRound);
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function updateAnswer(int256 _newAnswer) external {
        latestAnswer = _newAnswer;
        roundId++;
        answeredInRound = roundId;
        updateAt = block.timestamp;
    }

    function setStale() external {
        updateAt = 0;
    }

    function setRoundMismatch(uint80 _newRoundId) external {
        roundId = _newRoundId;
    }

    function setNegativePrice() external {
        latestAnswer = -1;
    }

    function setZeroPrice() external {
        latestAnswer = 0;
    }
}

///////////////////////////////////
//  Wrapper — library functions  //
///////////////////////////////////

contract PriceConverterWrapper {
    using PriceConverter for AggregatorV3Interface;

    function getEthUsdPrice(AggregatorV3Interface feed) external view returns (uint256) {
        return feed.getEthUsdPrice();
    }

    function weiToUsd(AggregatorV3Interface feed, uint256 weiAmount) external view returns (uint256) {
        return feed.weiToUsd(weiAmount);
    }

    function calculateGasFeeWei(uint256 gasUsed, uint256 gasPrice) external pure returns (uint256) {
        return PriceConverter.calculateGasFeeWei(gasUsed, gasPrice);
    }

    function calculateGasFeeUsd(uint256 gasUsed, uint256 gasPrice, AggregatorV3Interface feed)
        external
        view
        returns (uint256)
    {
        return PriceConverter.calculateGasFeeUsd(gasUsed, gasPrice, feed);
    }

    function usdToWei(uint256 usdAmount, AggregatorV3Interface feed) external view returns (uint256) {
        return PriceConverter.usdToWei(usdAmount, feed);
    }

    function getPriceFeedDecimals(AggregatorV3Interface feed) external view returns (uint8) {
        return PriceConverter.getPriceFeedDecimals(feed);
    }

    function getPriceFeedDescription(AggregatorV3Interface feed) external view returns (string memory) {
        return PriceConverter.getPriceFeedDescription(feed);
    }
}

///////////////////////
//   Test Contract   //
///////////////////////

contract PriceConverterTest is Test {
    MockV3Aggregator mockFeed;
    PriceConverterWrapper wrapper;

    int256 constant ETH_PRICE = 2000e8;
    uint256 constant GAS_USED = 21000;
    uint256 constant GAS_PRICE = 20 gwei;

    function setUp() public {
        mockFeed = new MockV3Aggregator(8, ETH_PRICE);
        wrapper = new PriceConverterWrapper();
    }

    ////////////////////////////////
    //  getEthUsdPrice Tests      //
    ////////////////////////////////

    function test_GetEthUsdPrice_ReturnsCorrectPrice() public view {
        uint256 price = wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
        assertEq(price, 2000e18);
    }

    function test_GetEthUsdPrice_Revert_StalePrice() public {
        mockFeed.setStale();
        vm.expectRevert(PriceConverter.PriceConverter__StalePrice.selector);
        wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
    }

    function test_GetEthUsdPrice_Revert_StalePrice_Timeout() public {
        vm.warp(block.timestamp + 4 hours);
        vm.expectRevert(PriceConverter.PriceConverter__StalePrice.selector);
        wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
    }

    function test_GetEthUsdPrice_Revert_ZeroPrice() public {
        mockFeed.setZeroPrice();
        vm.expectRevert(PriceConverter.PriceConverter__InvalidPrice.selector);
        wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
    }

    function test_GetEthUsdPrice_Revert_NegativePrice() public {
        mockFeed.setNegativePrice();
        vm.expectRevert(PriceConverter.PriceConverter__InvalidPrice.selector);
        wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
    }

    function test_GetEthUsdPrice_Revert_InvalidRound() public {
        // mockFeed.setInvalidRound();
        mockFeed.setRoundMismatch(5);
        vm.expectRevert(PriceConverter.PriceConverter__InvalidRound.selector);
        wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
    }

    ////////////////////////////////
    //  weiToUsd Tests            //
    ////////////////////////////////

    function test_WeiToUsd_OneEther() public view {
        uint256 usd = wrapper.weiToUsd(AggregatorV3Interface(address(mockFeed)), 1 ether);
        assertEq(usd, 2000e18); // 1 ETH = $2000
    }

    function test_WeiToUsd_ZeroAmount() public view {
        uint256 usd = wrapper.weiToUsd(AggregatorV3Interface(address(mockFeed)), 0);
        assertEq(usd, 0);
    }

    function test_WeiToUsd_HalfEther() public view {
        uint256 usd = wrapper.weiToUsd(AggregatorV3Interface(address(mockFeed)), 0.5 ether);
        assertEq(usd, 1000e18);
    }

    ////////////////////////////////
    //  calculateGasFeeWei Tests  //
    ////////////////////////////////

    function test_CalculateGasFeeWei_Correct() public view {
        uint256 fee = wrapper.calculateGasFeeWei(GAS_USED, GAS_PRICE);
        assertEq(fee, 420000000000000);
    }

    function test_CalculateGasFeeWei_ZeroGas() public view {
        uint256 fee = wrapper.calculateGasFeeWei(0, GAS_PRICE);
        assertEq(fee, 0);
    }

    ////////////////////////////////
    //  calculateGasFeeUsd Tests  //
    ////////////////////////////////

    function test_CalculateGasFeeUsd_Correct() public view {
        uint256 feeUsd = wrapper.calculateGasFeeUsd(GAS_USED, GAS_PRICE, AggregatorV3Interface(address(mockFeed)));
        uint256 expectedWei = GAS_USED * GAS_PRICE; // 21000 * 20 gwei = 420000000000000 wei
        uint256 expectedUsd = wrapper.weiToUsd(AggregatorV3Interface(address(mockFeed)), expectedWei);
        assertEq(feeUsd, expectedUsd);
    }

    ////////////////////////////////
    //  usdToWei Tests            //
    ////////////////////////////////

    function test_UsdToWei_Correct() public view {
        uint256 wei_ = wrapper.usdToWei(2000e18, AggregatorV3Interface(address(mockFeed)));
        assertEq(wei_, 1 ether);
    }

    ////////////////////////////////
    //  getPriceFeedDecimals      //
    ////////////////////////////////

    function test_GetPriceFeedDecimals_ReturnsCorrect() public view {
        uint8 dec = wrapper.getPriceFeedDecimals(AggregatorV3Interface(address(mockFeed)));
        assertEq(dec, 8);
    }

    ////////////////////////////////
    //  getPriceFeedDescription   //
    ////////////////////////////////

    function test_GetPriceFeedDescription_ReturnsCorrect() public view {
        string memory desc = wrapper.getPriceFeedDescription(AggregatorV3Interface(address(mockFeed)));
        assertEq(desc, "ETH / USD");
    }

    ////////////////////////////////
    //  Price Update Tests        //
    ////////////////////////////////

    function test_UpdateAnswer_ReflectsNewPrice() public {
        mockFeed.updateAnswer(3000e8);
        uint256 price = wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
        assertEq(price, 3000e18);
    }

    ////////////////////////////////
    //  Fuzz Tests                //
    ////////////////////////////////

    function testFuzz_WeiToUsd_AnyAmount(uint256 amount) public view {
        vm.assume(amount < 1_000_000 ether);
        uint256 usd = wrapper.weiToUsd(AggregatorV3Interface(address(mockFeed)), amount);
        assertEq(usd, (amount * 2000e18) / 1e18);
    }

    function testFuzz_CalculateGasFeeWei(uint256 gasUsed, uint256 gasPrice) public view {
        vm.assume(gasUsed < 1_000_000);
        vm.assume(gasPrice < 1000 gwei);
        uint256 fee = wrapper.calculateGasFeeWei(gasUsed, gasPrice);
        assertEq(fee, gasUsed * gasPrice);
    }
}
