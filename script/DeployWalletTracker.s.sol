// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import "../src/WalletRegistry.sol";
import "../src/TransactionTracker.sol";
import "../src/TrackerStorage.sol";

contract HelperConfig is Script {
    /////////////////
    //  Struct     //
    /////////////////

    struct NetWorkConfig {
        address ethUsdPriceFeed;
        uint256 deployerKey;
    }

    //////////////////////
    //  Constants       //
    //////////////////////

    address constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant MAINNET_ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    uint256 constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /////////////////////
    // State Variables //
    /////////////////////

    NetWorkConfig public activeConfig;

    ///////////////////
    //  Constructor  //
    ///////////////////

    constructor() {
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else if (block.chainid == 1) {
            activeConfig = getMainnetConfig();
        } else {
            activeConfig = getOrCreateAnvilConfig();
        }
    }

    //////////////////////
    //  Network Configs //
    //////////////////////

    function getSepoliaConfig() public view returns (NetWorkConfig memory) {
        return NetWorkConfig({ethUsdPriceFeed: SEPOLIA_ETH_USD_FEED, deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getMainnetConfig() public view returns (NetWorkConfig memory) {
        return NetWorkConfig({ethUsdPriceFeed: MAINNET_ETH_USD_FEED, deployerKey: vm.envUint("PRIVATE_KEY")});
    }

    function getOrCreateAnvilConfig() public returns (NetWorkConfig memory) {
        if (activeConfig.ethUsdPriceFeed != address(0)) {
            return activeConfig;
        }

        console.log("Deploying Mock Price Feed for Anvil...");

        vm.startBroadcast();
        MockV3Aggregator mockFeed = new MockV3Aggregator(18, 2000e8);
        vm.stopBroadcast();

        console.log("Mock Price Feed deployed at: ", address(mockFeed));

        return NetWorkConfig({ethUsdPriceFeed: address(mockFeed), deployerKey: ANVIL_PRIVATE_KEY});
    }
}

contract MockV3Aggregator {
    uint8 public decimals;
    int256 public latestAnswer;
    uint80 public latestRound;
    uint256 public latestTimestamp;

    constructor(uint8 _decimals, int256 __initialAnswer) {
        decimals = _decimals;
        latestAnswer = __initialAnswer;
        latestRound = 1;
        latestTimestamp = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updateAt, uint80 answeredInRound)
    {
        return (latestRound, latestAnswer, latestTimestamp, latestTimestamp, latestRound);
    }

    function description() external pure returns (string memory) {
        return "ETH / USD";
    }

    function updateAnswer(int256 _answer) external {
        latestAnswer = _answer;
        latestRound++;
        latestTimestamp = block.timestamp;
    }
}

contract DeployWalletTracker is Script {
    /////////////////////
    // State Variables //
    /////////////////////

    HelperConfig helperConfig;

    //////////////////////
    //  Main Function   //
    //////////////////////

    function run() external returns (WalletRegistry, TransactionTracker, TrackerStorage, HelperConfig) {
        helperConfig = new HelperConfig();
        (address ethUsdPriceFeed, uint256 deployerKey) = (helperConfig.activeConfig());

        console.log("===========================================");
        console.log("   Deploying WalletTracker Contracts...   ");
        console.log("===========================================");
        console.log("Network Chain ID: ", block.chainid);
        console.log("Price Feed:", ethUsdPriceFeed);

        vm.startBroadcast(deployerKey);

        WalletRegistry walletRegistry = new WalletRegistry();
        console.log("WalletRegistry deployed at: ", address(walletRegistry));

        TransactionTracker transactionTracker = new TransactionTracker(address(walletRegistry));
        console.log("TransactionTracker deployed at:", address(transactionTracker));

        TrackerStorage trackerStorage = new TrackerStorage(ethUsdPriceFeed, address(walletRegistry));
        console.log("TrackerStorage deployed at:", address(trackerStorage));

        trackerStorage.setAuthorizedTracker(address(transactionTracker));
        console.log("TransactionTracker authorized in TrackerStorage!");

        vm.stopBroadcast();

        console.log("===========================================");
        console.log("        Deployment Complete!              ");
        console.log("===========================================");

        return (walletRegistry, transactionTracker, trackerStorage, helperConfig);
    }
}
