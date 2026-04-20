// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./WalletRegistry.sol";

contract TransactionTracker is ReentrancyGuard, Ownable, Pausable {
    ////////////
    // Errors //
    ////////////
    error TransactionTracker__WalletNotRegistered();
    error TransactionTracker__ZeroAmount();
    error TransactionTracker__TransferFailed();
    error TransactionTracker__SameAddress();

    //////////////
    //  struct  //
    //////////////

    enum TxType {
        SENT,
        RECEIVED
    }

    struct Transaction {
        address from;
        address to;
        uint256 amount;
        uint256 gasPrice;
        uint256 gasLimit;
        uint256 timeStamp;
        TxType txType;
    }

    /////////////////////
    // State Variables //
    /////////////////////

    WalletRegistry private immutable i_walletRegistry;

    mapping(address => Transaction[]) private s_transactions;
    mapping(address => uint256) private s_totalTxCount;
    mapping(address => uint256) private s_totalEthSent;
    mapping(address => uint256) private s_totalEthReceived;

    ////////////
    // Events //
    ////////////

    event ethSent(
        address indexed from, address indexed to, uint256 amount, uint256 gasPrice, uint256 gasLimit, uint256 timeStamp
    );
    event ethReceived(
        address indexed from, address indexed to, uint256 amount, uint256 gasPrice, uint256 gasLimit, uint256 timeStamp
    );

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyRegistered() {
        if (!i_walletRegistry.isWalletRegistered(msg.sender)) {
            revert TransactionTracker__WalletNotRegistered();
        }
        _;
    }

    modifier moreThanZero() {
        if (msg.value == 0) {
            revert TransactionTracker__ZeroAmount();
        }
        _;
    }

    ///////////////////
    //  constructor  //
    ///////////////////

    constructor(address _walletRegistry) Ownable(msg.sender) {
        i_walletRegistry = WalletRegistry(_walletRegistry);
    }

    ////////////////////////
    // External Functions //
    ////////////////////////

    function sendEth(address payable _to, uint256 _gasPrice, uint256 _gasLimit)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyRegistered
        moreThanZero
    {
        if (_to == address(0)) revert TransactionTracker__ZeroAmount();
        if (_to == msg.sender) revert TransactionTracker__SameAddress();

        s_transactions[msg.sender].push(
            Transaction({
                from: msg.sender,
                to: _to,
                amount: msg.value,
                gasPrice: _gasPrice,
                gasLimit: _gasLimit,
                timeStamp: block.timestamp,
                txType: TxType.SENT
            })
        );

        if (i_walletRegistry.isWalletRegistered(_to)) {
            s_transactions[_to].push(
                Transaction({
                    from: msg.sender,
                    to: _to,
                    amount: msg.value,
                    gasPrice: _gasPrice,
                    gasLimit: _gasLimit,
                    timeStamp: block.timestamp,
                    txType: TxType.RECEIVED
                })
            );
            s_totalEthReceived[_to] += msg.value;
            s_totalTxCount[_to]++;
        }

        s_totalEthSent[msg.sender] += msg.value;
        s_totalTxCount[msg.sender]++;

        (bool success,) = _to.call{value: msg.value}("");
        if (!success) revert TransactionTracker__TransferFailed();

        emit ethSent(msg.sender, _to, msg.value, _gasPrice, _gasLimit, block.timestamp);
        emit ethReceived(msg.sender, _to, msg.value, _gasPrice, _gasLimit, block.timestamp);
    }

    ///////////////////////
    //  Owner Functions  //
    ///////////////////////

    function pauseContract() external onlyOwner {
        _pause();
    }

    function UnpausedContract() external onlyOwner {
        _unpause();
    }

    //////////////////////
    //  View Functions  //
    //////////////////////

    function getTransactions(address _wallet) external view returns (Transaction[] memory) {
        return s_transactions[_wallet];
    }

    function getMonthlyTransactions(address _wallet, uint256 _monthStart, uint256 _monthEnd)
        external
        view
        returns (Transaction[] memory)
    {
        Transaction[] memory allTxs = s_transactions[_wallet];
        uint256 count = 0;

        for (uint256 i = 0; i < allTxs.length; i++) {
            if (allTxs[i].timeStamp >= _monthStart && allTxs[i].timeStamp <= _monthEnd) {
                count++;
            }
        }

        Transaction[] memory monthlyTxs = new Transaction[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allTxs.length; i++) {
            if (allTxs[i].timeStamp >= _monthStart && allTxs[i].timeStamp <= _monthEnd) {
                monthlyTxs[index] = allTxs[i];
                index++;
            }
        }
        return monthlyTxs;
    }

    function getWalletStats(address _wallet)
        external
        view
        returns (uint256 totalTx, uint256 totalSent, uint256 totalReceived)
    {
        return (s_totalTxCount[_wallet], s_totalEthSent[_wallet], s_totalEthReceived[_wallet]);
    }

    function getRegistryAddress() external view returns (address) {
        return address(i_walletRegistry);
    }
}
