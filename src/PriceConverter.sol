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
        (uint80 roundId, int256 answer,/* uint256 startAt */, uint256 updatedAt, uint80 answerInRoundId) =
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

        if (answer < 0) {
            revert PriceConverter__InvalidPrice();
        }

        price = uint256(answer) * 1e10; // Convert to 18 decimals
        return price;
    }

    function weiToUsd(AggregatorV3Interface priceFeed, uint256 weiAmount) internal view returns (uint256 usdAmount) {
        uint256 ethPrice = getEthUsdPrice(priceFeed);
        usdAmount = (weiAmount * ethPrice) / 1e18; // Convert back to 18 decimals
        return usdAmount;
    }

    function calculateGasFeeWei(uint256 gasUsed, uint256 gasPrice) internal pure returns (uint256 gasFeeWei) {
        gasFeeWei = gasUsed * gasPrice;
        return gasFeeWei;
    }

    function calculateGasFeeUsd(uint256 gasUsed, uint256 gasPrice, AggregatorV3Interface priceFeed)
        internal
        view
        returns (uint256 gasFeeUsd)
    {
        uint256 gasFeeWei = calculateGasFeeWei(gasUsed, gasPrice);
        gasFeeUsd = weiToUsd(priceFeed, gasFeeWei);
        return gasFeeUsd;
    }

    function usdToWei(uint256 usdAmount, AggregatorV3Interface priceFeed) internal view returns (uint256 weiAmount) {
        uint256 ethPrice = getEthUsdPrice(priceFeed);
        weiAmount = (usdAmount * 1e18) / ethPrice; // Convert back to 18 decimals
        return weiAmount;
    }

    function getPriceFeedDecimals(AggregatorV3Interface priceFeed) internal view returns (uint8 decimals) {
        decimals = priceFeed.decimals();
        return decimals;
    }

    function getPriceFeedDescription(AggregatorV3Interface priceFeed)
        internal
        view
        returns (string memory description)
    {
        description = priceFeed.description();
        return description;
    }
}
