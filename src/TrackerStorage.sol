// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./PriceConverter.sol";
import "./WalletRegistry.sol";

contract TrackerStorage is ReentrancyGuard, Ownable {
    //////////////////////
    //  Library Usage   //
    //////////////////////

    using PriceConverter for AggregatorV3Interface;

    ////////////
    // Errors //
    ////////////

    error TrackerStorage__NotRegistered();
    error TrackerStorage__NotAuthorized();
    error TrackerStorage__InvalidMonth();
    error TrackerStorage__InvalidYear();
    error TrackerStorage__ZeroAddress();

    //////////////
    //  struct  //
    //////////////

    struct MonthlyStats {
        uint256 totalTransactions;
        uint256 totalEthSentWei;
        uint256 totalEthReceivedWei;
        uint256 totalGasFeeWei;
        uint256 totalEthSentUsd;
        uint256 totalEthReceivedUsd;
        uint256 totalGasFeeUsd;
        uint256 lastUpdated;
    }

    struct TxRecord {
        address from;
        address to;
        uint256 amountWei;
        uint256 amountUsd;
        uint256 gasFeeWei;
        uint256 gasFeeUsd;
        uint256 gasUsed;
        uint256 gasPrice;
        uint256 timeStamp;
        uint8 month;
        uint16 year;
        bool isSent;
    }

    /////////////////////
    // State Variables //
    /////////////////////

    AggregatorV3Interface private immutable i_priceFeed;
    WalletRegistry private immutable i_walletRegistry;
    address private s_authorizedTracker;

    mapping(address => mapping(uint16 => mapping(uint8 => MonthlyStats))) private s_monthlyStats;
    mapping(address => TxRecord[]) private s_allTransactions;
    mapping(address => uint256) private s_TxCount;
    mapping(address => uint256) private s_ethSent;
    mapping(address => uint256) private s_ethReceived;
    mapping(address => uint256) private s_gasFees;

    ////////////
    // Events //
    ////////////

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

    event MonthlyStatsUpdated(
        address indexed wallet, uint8 month, uint16 year, uint256 totalTx, uint256 totalGasFeeUsd
    );

    event AuthorizedTrackerSet(address indexed tracker);

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyAuthorized() {
        if (msg.sender != s_authorizedTracker) {
            revert TrackerStorage__NotAuthorized();
        }
        _;
    }

    modifier onlyRegistered(address wallet) {
        if (!i_walletRegistry.isWalletRegistered(wallet)) {
            revert TrackerStorage__NotRegistered();
        }
        _;
    }

    ///////////////////
    //  constructor  //
    ///////////////////

    constructor(address _priceFeed, address _walletRegistry) Ownable(msg.sender) {
        if (_priceFeed == address(0) || _walletRegistry == address(0)) {
            revert TrackerStorage__ZeroAddress();
        }
        i_priceFeed = AggregatorV3Interface(_priceFeed);
        i_walletRegistry = WalletRegistry(_walletRegistry);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    function setAuthorizedTracker(address _tracker) external onlyOwner {
        if (_tracker == address(0)) {
            revert TrackerStorage__ZeroAddress();
        }
        s_authorizedTracker = _tracker;
        emit AuthorizedTrackerSet(_tracker);
    }

    function recordTransaction(
        address _wallet,
        address _to,
        uint256 _amountWei,
        uint256 _gasUsed,
        uint256 _gasPrice,
        bool _isSent
    ) external nonReentrant onlyAuthorized onlyRegistered(_wallet) {
        uint256 amountUsd = i_priceFeed.weiToUsd(_amountWei);
        uint256 gasFeeWei = PriceConverter.calculateGasFeeWei(_gasUsed, _gasPrice);
        uint256 gasFeeUsd = i_priceFeed.weiToUsd(gasFeeWei);

        (uint8 month, uint16 year) = _getCurrentMonthYear();

        TxRecord memory newTx = TxRecord({
            from: _isSent ? _wallet : _to,
            to: !_isSent ? _wallet : _to,
            amountWei: _amountWei,
            amountUsd: amountUsd,
            gasFeeWei: gasFeeWei,
            gasFeeUsd: gasFeeUsd,
            gasUsed: _gasUsed,
            gasPrice: _gasPrice,
            timeStamp: block.timestamp,
            month: month,
            year: year,
            isSent: _isSent
        });

        s_allTransactions[_wallet].push(newTx);

        _updateMonthlyStats(_wallet, _amountWei, amountUsd, gasFeeWei, gasFeeUsd, month, year, _isSent);
        _updateLifetimeStats(_wallet, _amountWei, gasFeeWei, _isSent);

        emit txRecorded(_wallet, _amountWei, amountUsd, gasFeeWei, gasFeeUsd, month, year, _isSent, block.timestamp);
    }

    ///////////////////////
    // Private Functions //
    ///////////////////////

    function _updateMonthlyStats(
        address _wallet,
        uint256 _amountWei,
        uint256 _amountUsd,
        uint256 _gasFeeWei,
        uint256 _gasFeeUsd,
        uint8 _month,
        uint16 _year,
        bool _isSent
    ) private {
        MonthlyStats storage stats = s_monthlyStats[_wallet][_year][_month];

        stats.totalTransactions++;
        stats.totalGasFeeWei += _gasFeeWei;
        stats.totalGasFeeUsd += _gasFeeUsd;
        stats.lastUpdated = block.timestamp;

        if (_isSent) {
            stats.totalEthSentWei += _amountWei;
            stats.totalEthSentUsd += _amountUsd;
        } else {
            stats.totalEthReceivedWei += _amountWei;
            stats.totalEthReceivedUsd += _amountUsd;
        }

        emit MonthlyStatsUpdated(_wallet, _month, _year, stats.totalTransactions, stats.totalGasFeeUsd);
    }

    function _updateLifetimeStats(address _wallet, uint256 _amountWei, uint256 _gasFeeWei, bool _isSent) private {
        s_TxCount[_wallet]++;
        s_gasFees[_wallet] += _gasFeeWei;

        if (_isSent) {
            s_ethSent[_wallet] += _amountWei;
        } else {
            s_ethReceived[_wallet] += _amountWei;
        }
    }

    function _getCurrentMonthYear() private view returns (uint8 month, uint16 year) {
        uint256 timeStamp = block.timestamp;
        uint256 SECONDS_PER_DAY = 86400;
        uint256 SECONDS_PER_YEAR = SECONDS_PER_DAY * 365;

        uint256 calculatedYear = 1970 + timeStamp / SECONDS_PER_YEAR;
        year = uint16(calculatedYear);
        uint256 dayOfYear = (timeStamp % SECONDS_PER_YEAR) / SECONDS_PER_DAY;

        if (dayOfYear < 31) month = 1;
        else if (dayOfYear < 59) month = 2;
        else if (dayOfYear < 90) month = 3;
        else if (dayOfYear < 120) month = 4;
        else if (dayOfYear < 151) month = 5;
        else if (dayOfYear < 181) month = 6;
        else if (dayOfYear < 212) month = 7;
        else if (dayOfYear < 243) month = 8;
        else if (dayOfYear < 273) month = 9;
        else if (dayOfYear < 304) month = 10;
        else if (dayOfYear < 334) month = 11;
        else month = 12;

        return (month, year);
    }

    ////////////////////
    // View Functions //
    ////////////////////

    function getMonthlyStats(address _wallet, uint8 _month, uint16 _year) external view returns (MonthlyStats memory) {
        if (_month < 1 || _month > 12) revert TrackerStorage__InvalidMonth();
        if (_year < 2024) revert TrackerStorage__InvalidYear();
        return s_monthlyStats[_wallet][_year][_month];
    }

    function getAllTransactions(address _wallet) external view returns (TxRecord[] memory) {
        return s_allTransactions[_wallet];
    }

    function getLifetimeStats(address _wallet)
        external
        view
        returns (
            uint256 totaltx,
            uint256 ethSentInWei,
            uint256 ethReceivedWei,
            uint256 totalGasFeeWei,
            uint256 ethSentUsd,
            uint256 ethReceivedUsd,
            uint256 totalGasFeeUsd
        )
    {
        totaltx = s_TxCount[_wallet];
        ethSentInWei = s_ethSent[_wallet];
        ethReceivedWei = s_ethReceived[_wallet];
        totalGasFeeWei = s_gasFees[_wallet];

        ethSentUsd = i_priceFeed.weiToUsd(ethSentInWei);
        ethReceivedUsd = i_priceFeed.weiToUsd(ethReceivedWei);
        totalGasFeeUsd = i_priceFeed.weiToUsd(totalGasFeeWei);
    }

    function getCurrentEthPrice() external view returns (uint256) {
        return i_priceFeed.getEthUsdPrice();
    }

    function getAuthorizedTracker() external view returns (address) {
        return s_authorizedTracker;
    }

    function getPriceFeed() external view returns (address) {
        return address(i_priceFeed);
    }
}
