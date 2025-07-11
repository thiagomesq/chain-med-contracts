// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;
/**
 * @title DeployZKVerifier
 * @author Thiago Mesquita
 * @notice Script to deploy the ZKVerifier contract
 * @dev This script deploys the ZKVerifier contract and verifies it on Etherscan
 */

import {Script} from "forge-std/Script.sol";
import {ZKVerifier} from "src/ZKVerifier.sol";

contract DeployZKVerifier is Script {
    function run() external returns (ZKVerifier) {
        vm.startBroadcast();
        ZKVerifier zkVerifier = new ZKVerifier(0x5FbDB2315678afecb367f032d93F642f64180aa3);
        vm.stopBroadcast();
        return zkVerifier;
    }
}
