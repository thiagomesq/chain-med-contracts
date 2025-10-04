// SPDX-License-Identifier: MIT

pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {UserRegistry} from "src/UserRegistry.sol";
import {DoctorRegistry} from "src/DoctorRegistry.sol";
import {DPSManager} from "src/DPSManager.sol";
import {ChainMedAutomation} from "src/ChainMedAutomation.sol";
import {MedicalAssetToken} from "src/MedicalAssetToken.sol";
import {PrescriptionManager} from "src/PrescriptionManager.sol";
import {PrescriptionToken} from "src/PrescriptionToken.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployChainMedDPS is Script {
    function run()
        external
        returns (
            UserRegistry,
            DoctorRegistry,
            PrescriptionToken,
            PrescriptionManager,
            DPSManager,
            ChainMedAutomation,
            MedicalAssetToken,
            HelperConfig.NetworkConfig memory
        )
    {
        return DeployContracts();
    }

    function DeployContracts()
        public
        returns (
            UserRegistry,
            DoctorRegistry,
            PrescriptionToken,
            PrescriptionManager,
            DPSManager,
            ChainMedAutomation,
            MedicalAssetToken,
            HelperConfig.NetworkConfig memory
        )
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

        DoctorRegistry doctorRegistry = new DoctorRegistry();

        // Deploy the PrescriptionToken contract
        PrescriptionToken prescriptionToken = new PrescriptionToken();

        PrescriptionManager prescriptionManager = new PrescriptionManager({
            _userRegistryAddress: address(userRegistry),
            _doctorRegistryAddress: address(doctorRegistry),
            _prescriptionTokenAddress: address(prescriptionToken)
        });

        DPSManager dpsManager = new DPSManager({_userRegistryAddress: address(userRegistry)});

        ChainMedAutomation chainMedAutomation = new ChainMedAutomation({
            _userRegistryAddress: address(userRegistry),
            _dpsManagerAddress: address(dpsManager),
            _prescriptionManagerAddress: address(prescriptionManager)
        });

        MedicalAssetToken medicalAssetToken = new MedicalAssetToken({
            _userRegistryAddress: address(userRegistry),
            _dpsManagerAddress: address(dpsManager)
        });

        // Set the DPSManager in UserRegistry
        userRegistry.setDPSManagerContract({_dpsManagerAddress: address(dpsManager)});

        // Set the Automation contract in UserRegistry
        userRegistry.setAutomationContract({_automationAddress: address(chainMedAutomation)});

        // Set the Automation contract in PrescriptionManager
        prescriptionManager.setAutomationContract({_automationAddress: address(chainMedAutomation)});

        // Set the MedicalAssetToken in DPSManager
        dpsManager.setMedicalAssetToken({_medicalAssetTokenAddress: address(medicalAssetToken)});

        vm.stopBroadcast();

        return (
            userRegistry,
            doctorRegistry,
            prescriptionToken,
            prescriptionManager,
            dpsManager,
            chainMedAutomation,
            medicalAssetToken,
            config
        );
    }
}
