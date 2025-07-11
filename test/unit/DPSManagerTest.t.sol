// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {DeployChainMedDPS} from "script/DeployChainMedDPS.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {UserRegistry} from "src/UserRegistry.sol";
import {DPSManager} from "src/DPSManager.sol";
import {ChainMedAutomation} from "src/ChainMedAutomation.sol";
import {MedicalAssetToken} from "src/MedicalAssetToken.sol";

contract DPSManagerTest is Test {
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
    address private insurance;
    address private nonOwner;

    // Dados de Teste
    string private constant USER1_NAME = "User One";
    bytes32 private constant USER1_HASH = keccak256(abi.encodePacked("user1_hash"));
    bytes32 private constant USER2_HASH = keccak256(abi.encodePacked("user2_hash"));
    bytes32 private constant DPS1_HASH = keccak256(abi.encodePacked("dps1_hash"));
    string private constant DPS1_DATA = "eyJkYXRhIjoiZHBzMSJ9";

    function setUp() public {
        deployer = new DeployChainMedDPS();
        (userRegistry, dpsManager, chainMedAutomation, medicalAssetToken, config) = deployer.run();

        owner = config.account;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        insurance = makeAddr("insurance");
        nonOwner = makeAddr("nonOwner");

        // Pré-condição: Registrar usuários para que possam interagir com o DPSManager
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);
        vm.prank(user2);
        userRegistry.registerUser("User Two", USER2_HASH);
    }

    // ////////////////////////////////////
    // Testes de Registro de DPS       //
    // ////////////////////////////////////

    function testRegisterDPSSuccess() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit DPSManager.DPSRegistered(0, user1, DPS1_HASH, DPS1_DATA, block.timestamp);
        dpsManager.registerDPS(DPS1_HASH, USER1_HASH, new bytes32[](0), DPS1_DATA);

        // Verifica o estado
        assertEq(dpsManager.getDPSCount(), 1);
        assertEq(dpsManager.getUserDPSCount(USER1_HASH), 1);

        DPSManager.DPS memory dps = dpsManager.getDPSInfo(0);
        assertEq(dps.hashDPS, DPS1_HASH);
        assertEq(dps.responsibleHash, USER1_HASH);

        // Verifica se o token foi mintado
        assertEq(medicalAssetToken.ownerOf(0), user1);
        assertEq(medicalAssetToken.tokenURI(0), string.concat("data:application/json;base64,", DPS1_DATA));
    }

    function testRegisterDPSSuccessWithDependents() public {
        bytes32[] memory dependents = new bytes32[](1);
        dependents[0] = USER2_HASH;

        vm.prank(user1);
        dpsManager.registerDPS(DPS1_HASH, USER1_HASH, dependents, DPS1_DATA);

        assertEq(dpsManager.getUserDPSCount(USER1_HASH), 1);
        assertEq(dpsManager.getUserDPSCount(USER2_HASH), 1);
    }

    function testRevertIfRegisterDPSFromInactiveUser() public {
        // Desativa o usuário
        vm.prank(address(chainMedAutomation));
        userRegistry.deactivateUser(user1);

        vm.prank(user1);
        vm.expectRevert(DPSManager.DPSManager__UserNotActive.selector);
        dpsManager.registerDPS(DPS1_HASH, USER1_HASH, new bytes32[](0), DPS1_DATA);
    }

    function testRevertIfRegisterDPSWhenTokenContractNotSet() public {
        // Cria um novo DPSManager sem o token setado
        DPSManager newDpsManager = new DPSManager(address(userRegistry));

        vm.prank(user1);
        vm.expectRevert(DPSManager.DPSManager__MedicalAssetTokenNotSet.selector);
        newDpsManager.registerDPS(DPS1_HASH, USER1_HASH, new bytes32[](0), DPS1_DATA);
    }

    // ////////////////////////////////////
    // Testes de Funções de Gerenciamento //
    // ////////////////////////////////////

    function testSetMedicalAssetTokenSuccess() public {
        DPSManager newDpsManager = new DPSManager(address(userRegistry));
        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit DPSManager.MedicalAssetTokenSet(address(medicalAssetToken));
        newDpsManager.setMedicalAssetToken(address(medicalAssetToken));
    }

    function testRevertIfSetMedicalAssetTokenAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert(DPSManager.DPSManager__MedicalAssetTokenAlreadySet.selector);
        dpsManager.setMedicalAssetToken(address(0x123));
    }

    // ////////////////////////////////////
    // Testes de Consulta de DPS (Query) //
    // ////////////////////////////////////

    function testRevertIfQueryDPSFromUnauthorizedInsurance() public {
        vm.prank(insurance); // Não é uma seguradora autorizada
        vm.expectRevert(DPSManager.DPSManager__InsuranceNotAuthorized.selector);
        dpsManager.queryDPS(USER1_HASH);
    }

    // ////////////////////////////////////
    // Testes de Consulta de Usuário    //
    // ////////////////////////////////////

    function testRevertIfQueryUserFromUnauthorizedInsurance() public {
        vm.prank(insurance); // Não é uma seguradora autorizada
        vm.expectRevert(DPSManager.DPSManager__InsuranceNotAuthorized.selector);
        dpsManager.queryDPS(USER1_HASH);
    }

    // ////////////////////////////////////
    // Testes de Eventos                //
    // ////////////////////////////////////

    function testEventEmittedOnRegister() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit DPSManager.DPSRegistered(0, user1, DPS1_HASH, DPS1_DATA, block.timestamp);
        dpsManager.registerDPS(DPS1_HASH, USER1_HASH, new bytes32[](0), DPS1_DATA);
    }

    function testEventEmittedOnSetMedicalAssetToken() public {
        DPSManager newDpsManager = new DPSManager(address(userRegistry));
        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit DPSManager.MedicalAssetTokenSet(address(medicalAssetToken));
        newDpsManager.setMedicalAssetToken(address(medicalAssetToken));
    }
}
