// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WalletRegistry
 * @author sanskar Gupta
 * @notice This contract allows users to register their wallets
 * @notice Transactions of registered wallets will be tracked
 * @dev Used OpenZepplin's ReentrancyGuard, Ownable and Pausable for security
 */

contract WalletRegistry is ReentrancyGuard, Ownable, Pausable {
    //////////////
    //  struct  //
    //////////////

    struct UserProfile {
        address walletAddress;
        uint256 registeredAt;
        uint256 latestUpdate;
        bool isActive;
        string userName;
    }

    ///////////////////////
    //  state variables  //
    ///////////////////////

    mapping(address => UserProfile) private s_userProfile;
    uint256 private s_totalRegistered;
    uint256 private constant MAX_USERNAME_LENGTH = 32;

    //////////////
    //  events  //
    //////////////

    event WalletRegistered(address indexed wallet, string userName, uint256 timetSamp);
    event WalletRemoved(address indexed wallet, uint256 timetSamp);
    event UserNameUpdated(address indexed wallet, string oldUserName, string newUserName);
    event ContractPaused(string reason);

    //////////////
    //  errors  //
    //////////////

    error WalletRegistry__AlreadyRegistered(address wallet);
    error WalletRegistry__NotRegistered(address wallet);
    error WalletRegistry__UsernameTooLong(uint256 length, uint256 maxlength);
    error WalletRegistry__EmptyUsername();
    error WalletRegistry__ZeroAddress();

    ///////////////////
    //  constructor  //
    ///////////////////

    constructor() Ownable(msg.sender) {
        s_totalRegistered = 0;
    }

    //////////////////////
    //  Main Functions  //
    //////////////////////

    function registerWallet(string calldata _username) external nonReentrant whenNotPaused {
        if (msg.sender == address(0)) {
            revert WalletRegistry__ZeroAddress();
        }

        if (s_userProfile[msg.sender].isActive) {
            revert WalletRegistry__AlreadyRegistered(msg.sender);
        }

        bytes memory userNameBytes = bytes(_username);
        if (userNameBytes.length == 0) {
            revert WalletRegistry__EmptyUsername();
        }

        if (userNameBytes.length > MAX_USERNAME_LENGTH) {
            revert WalletRegistry__UsernameTooLong(userNameBytes.length, MAX_USERNAME_LENGTH);
        }

        s_userProfile[msg.sender] = UserProfile({
            walletAddress: msg.sender,
            registeredAt: block.timestamp,
            latestUpdate: block.timestamp,
            isActive: true,
            userName: _username
        });

        s_totalRegistered++;

        emit WalletRegistered(msg.sender, _username, block.timestamp);
    }

    function removeWallet() external nonReentrant whenNotPaused {
        if (!s_userProfile[msg.sender].isActive) {
            revert WalletRegistry__NotRegistered(msg.sender);
        }

        s_userProfile[msg.sender].isActive = false;
        s_totalRegistered--;

        emit WalletRemoved(msg.sender, block.timestamp);
    }

    function updateUserName(string calldata _newUserName) external nonReentrant whenNotPaused {
        if (!s_userProfile[msg.sender].isActive) {
            revert WalletRegistry__NotRegistered(msg.sender);
        }

        bytes memory userNameBytes = bytes(_newUserName);
        if (userNameBytes.length == 0) {
            revert WalletRegistry__EmptyUsername();
        }

        if (userNameBytes.length > MAX_USERNAME_LENGTH) {
            revert WalletRegistry__UsernameTooLong(userNameBytes.length, MAX_USERNAME_LENGTH);
        }

        string memory oldUserName = s_userProfile[msg.sender].userName;

        s_userProfile[msg.sender].userName = _newUserName;
        s_userProfile[msg.sender].latestUpdate = block.timestamp;

        emit UserNameUpdated(msg.sender, oldUserName, _newUserName);
    }

    //////////////////////
    // Pause Functions  //
    //////////////////////

    function pauseContract() external onlyOwner {
        _pause();
        emit ContractPaused("Contract Paused");
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }

    //////////////////////
    //  View Functions  //
    //////////////////////

    function getUserProfile(address _wallet) external view returns (UserProfile memory) {
        if (!s_userProfile[_wallet].isActive) {
            revert WalletRegistry__NotRegistered(_wallet);
        }
        return s_userProfile[_wallet];
    }

    function isWalletRegistered(address _wallet) external view returns (bool) {
        return s_userProfile[_wallet].isActive;
    }

    function getTotalRegistered() external view returns (uint256) {
        return s_totalRegistered;
    }

    function isContractPaused() external view returns (bool) {
        return paused();
    }
}
