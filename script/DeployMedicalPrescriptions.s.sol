// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;
/**
 * @title DeployMedicalPrescriptions
 * @author Thiago Mesquita
 * @notice Script to deploy the MedicalPrescriptions contract
 * @dev This script deploys the MedicalPrescriptions contract and verifies it on Etherscan
 */

import {Script} from "forge-std/Script.sol";
import {MedicalPrescriptions} from "src/MedicalPrescriptions.sol";

contract DeployMedicalPrescriptions is Script {
    function run() external returns (MedicalPrescriptions) {
        vm.startBroadcast();
        MedicalPrescriptions medicalPrescriptions = new MedicalPrescriptions();
        vm.stopBroadcast();
        return medicalPrescriptions;
    }
}
