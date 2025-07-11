// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {DeployChainMedDPS} from "script/DeployChainMedDPS.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {UserRegistry} from "src/UserRegistry.sol";
import {DPSManager} from "src/DPSManager.sol";
import {ChainMedAutomation} from "src/ChainMedAutomation.sol";
import {MedicalAssetToken} from "src/MedicalAssetToken.sol";

contract ChainMedAutomationTest is Test {
    // Contratos e Configuração
    DeployChainMedDPS private deployer;
    UserRegistry private userRegistry;
    DPSManager private dpsManager;
    ChainMedAutomation private chainMedAutomation;
    MedicalAssetToken private medicalAssetToken;
    HelperConfig.NetworkConfig private config;

    // Usuários e Entidades
    address private owner;
    address private user1;
    address private user2;
    address private forwarder;
    address private nonOwner;

    // Dados de Teste
    string private constant USER1_NAME = "Stale User";
    bytes32 private constant USER1_HASH = keccak256(abi.encodePacked("stale_user_hash"));
    bytes32 private constant DPS1_HASH = keccak256(abi.encodePacked("stale_dps_hash"));
    string private constant DPS1_DATA = "data:application/json;base64,eyJkYXRhIjoiZHBzMSJ9";

    // Períodos de tempo para teste
    uint256 private constant USER_INACTIVE_PERIOD = 365 days;
    uint256 private constant DPS_STALE_PERIOD = 5 * 365 days;

    function setUp() public {
        deployer = new DeployChainMedDPS();
        (userRegistry, dpsManager, chainMedAutomation, medicalAssetToken, config) = deployer.run();

        owner = config.account;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        forwarder = makeAddr("forwarder");
        nonOwner = makeAddr("nonOwner");

        // Configura o forwarder no contrato de automação
        vm.prank(owner);
        chainMedAutomation.setAutomationForwarder(forwarder);
    }

    // ////////////////////////////////////
    // Testes de Configuração          //
    // ////////////////////////////////////

    function testSetBatchSizesSuccess() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ChainMedAutomation.UserBatchSizeSet(50);
        chainMedAutomation.setUserBatchSize(50);

        assertEq(chainMedAutomation.s_userBatchSize(), 50);
    }

    function testRevertIfSetBatchSizeToZero() public {
        vm.prank(owner);
        vm.expectRevert(ChainMedAutomation.ChainMedAutomation__BatchSizeCannotBeZero.selector);
        chainMedAutomation.setUserBatchSize(0);
    }

    // ////////////////////////////////////
    // Testes de checkUpkeep           //
    // ////////////////////////////////////

    function testCheckUpkeepReturnsFalseIfNoWorkNeeded() public view {
        (bool upkeepNeeded,) = chainMedAutomation.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueForStaleUser() public {
        // 1. Registra um usuário
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);

        // 2. Avança o tempo para torná-lo obsoleto
        vm.warp(block.timestamp + USER_INACTIVE_PERIOD + 1 days);

        // 3. Verifica se a manutenção é necessária
        (bool upkeepNeeded, bytes memory performData) = chainMedAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);
        assertTrue(performData.length > 0);
    }

    // ////////////////////////////////////
    // Testes de performUpkeep         //
    // ////////////////////////////////////

    function testPerformUpkeepDeactivatesStaleUser() public {
        // Setup: Cria um usuário obsoleto
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);
        vm.warp(block.timestamp + USER_INACTIVE_PERIOD + 1 days);

        // Pega os dados da manutenção
        (bool upkeepNeeded, bytes memory performData) = chainMedAutomation.checkUpkeep("");
        require(upkeepNeeded, "Upkeep should be needed");

        // Executa a manutenção
        vm.prank(forwarder);
        vm.expectEmit(true, true, false, true);
        emit ChainMedAutomation.UserDeactivated(user1);
        chainMedAutomation.performUpkeep(performData);

        // Verifica se o usuário foi desativado
        assertFalse(userRegistry.isUserActive(user1));
    }

    function testRevertIfPerformUpkeepNotFromForwarder() public {
        // Setup: Cria um usuário obsoleto para ter dados válidos
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);
        vm.warp(block.timestamp + USER_INACTIVE_PERIOD + 1 days);
        (, bytes memory performData) = chainMedAutomation.checkUpkeep("");

        // Tenta executar com uma conta não autorizada
        vm.prank(nonOwner);
        vm.expectRevert(ChainMedAutomation.ChainMedAutomation__InvalidForwarderAddress.selector);
        chainMedAutomation.performUpkeep(performData);
    }

    function testRevertIfPerformUpkeepWithNoData() public {
        bytes memory emptyData = abi.encode(new address[](0), new uint256[](0));

        vm.prank(forwarder);
        vm.expectRevert(ChainMedAutomation.ChainMedAutomation__NoUpkeepNeeded.selector);
        chainMedAutomation.performUpkeep(emptyData);
    }
}
