// SPDX-License-Identifier: MIT

pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {UserRegistry} from "src/UserRegistry.sol";
import {DPSManager} from "src/DPSManager.sol";
import {ChainMedAutomation} from "src/ChainMedAutomation.sol";
import {MedicalAssetToken} from "src/MedicalAssetToken.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployChainMedDPS is Script {
    function run()
        external
        returns (UserRegistry, DPSManager, ChainMedAutomation, MedicalAssetToken, HelperConfig.NetworkConfig memory)
    {
        return DeployContracts();
    }

    function DeployContracts()
        public
        returns (UserRegistry, DPSManager, ChainMedAutomation, MedicalAssetToken, HelperConfig.NetworkConfig memory)
    {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);

        UserRegistry userRegistry = new UserRegistry({
            _callbackGasLimit: config.callbackGasLimit,
            _functionsRouter: config.functionsRouter,
            _subscriptionId: config.subscriptionId,
            _donId: config.donId
        });

        DPSManager dpsManager = new DPSManager({_userRegistryAddress: address(userRegistry)});

        ChainMedAutomation chainMedAutomation = new ChainMedAutomation({
            _userRegistryAddress: address(userRegistry),
            _dpsManagerAddress: address(dpsManager)
        });

        MedicalAssetToken medicalAssetToken = new MedicalAssetToken({
            _userRegistryAddress: address(userRegistry),
            _dpsManagerAddress: address(dpsManager)
        });

        // Set the DPSManager in UserRegistry
        userRegistry.setDPSManagerContract({_dpsManagerAddress: address(dpsManager)});

        // Set the Automation contract in UserRegistry
        userRegistry.setAutomationContract({_automationAddress: address(chainMedAutomation)});

        // Set the MedicalAssetToken in DPSManager
        dpsManager.setMedicalAssetToken({_medicalAssetTokenAddress: address(medicalAssetToken)});

        vm.stopBroadcast();

        return (userRegistry, dpsManager, chainMedAutomation, medicalAssetToken, config);
    }
}
