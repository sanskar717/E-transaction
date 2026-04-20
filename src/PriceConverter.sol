// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/AggregatorV3Interface.sol";

library PriceConverter {
    ///////////////////////
    //  State Variables  //
    ///////////////////////

    uint256 private constant TIMEOUT = 3 hours;

    //////////////
    //  Errors  //
    //////////////

    error PriceConverter__StalePrice();
    error PriceConverter__InvalidPrice();
    error PriceConverter__InvalidRound();

    /////////////////
    //  Functions  //
    /////////////////

    function getEthUsdPrice(AggregatorV3Interface priceFeed) internal view returns (uint256 price) {
        (uint80 roundId, int256 answer, uint256 startAt, uint256 updatedAt, uint80 answerInRoundId) =
            priceFeed.latestRoundData();

        if (updatedAt == 0 || block.timestamp - updatedAt > TIMEOUT) {
            revert PriceConverter__StalePrice();
        }

        if (answer == 0) {
            revert PriceConverter__InvalidPrice();
        }

        if (answerInRoundId < roundId) {
            revert PriceConverter__InvalidRound();
        }

        price = uint256(answer) * 1e10; // Convert to 18 decimals
        return price;
    }

    function weiToUsd(uint256 weiAmount, AggregatorV3Interface priceFeed) internal view returns (uint256 usdAmount) {
        uint256 ethPrice = getEthUsdPrice(priceFeed);
        usdAmount = (weiAmount * ethPrice) / 1e18; // Convert back to 18 decimals
        return usdAmount;
    }
}
