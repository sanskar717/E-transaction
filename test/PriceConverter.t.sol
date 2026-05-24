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

    function updateAnswe(int256 _newAnswer) external {
        latestAnswer = _newAnswer;
        roundId++;
        updateAt = block.timestamp;
    }

    function setStale() external {
        updateAt = 0;
    }

    function setInvalidRound() external {
        answeredInRound = roundId + 1;
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
        wrapper = new  PriceConverterWrapper();
    }

    ////////////////////////////////
    //  getEthUsdPrice Tests      //
    ////////////////////////////////

    function test_GetEthUsdPrice_ReturnsCorrectPrice() public view{
        uint256 price = wrapper.getEthUsdPrice(AggregatorV3Interface(address(mockFeed)));
        assertEq(price, 2000e18);
    }
}
