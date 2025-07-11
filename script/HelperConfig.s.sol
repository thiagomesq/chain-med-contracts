// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    struct NetworkConfig {
        uint32 callbackGasLimit;
        uint64 subscriptionId;
        address functionsRouter;
        bytes32 donId;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getMainnetEthConfig();
    }

    function getConfigChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].functionsRouter != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigChainId(block.chainid);
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            callbackGasLimit: 100000,
            subscriptionId: 5241,
            functionsRouter: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            donId: 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000,
            account: 0xe7FDf6cA472c484FA8b7b2E11a5E62adaF1e649F
        });
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            callbackGasLimit: 100000,
            subscriptionId: 5241,
            functionsRouter: 0x65Dcc24F8ff9e51F10DCc7Ed1e4e2A61e6E14bd6,
            donId: 0x66756e2d657468657265756d2d6d61696e6e65742d3100000000000000000000,
            account: 0xe7FDf6cA472c484FA8b7b2E11a5E62adaF1e649F
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        localNetworkConfig = NetworkConfig({
            callbackGasLimit: 100000,
            subscriptionId: 5241,
            functionsRouter: 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0,
            donId: 0x66756e2d657468657265756d2d6d61696e6e65742d3100000000000000000000,
            account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        });
        return localNetworkConfig;
    }
}