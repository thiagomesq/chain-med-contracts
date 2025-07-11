// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {DeployChainMedDPS} from "script/DeployChainMedDPS.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {UserRegistry} from "src/UserRegistry.sol";
import {DPSManager} from "src/DPSManager.sol";
import {ChainMedAutomation} from "src/ChainMedAutomation.sol";
import {MedicalAssetToken} from "src/MedicalAssetToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UserRegistryTest is Test {
    // Contratos e Configuração
    DeployChainMedDPS private deployer;
    UserRegistry private userRegistry;
    DPSManager private dpsManager;
    ChainMedAutomation private chainMedAutomation;
    MedicalAssetToken private medicalAssetToken;
    HelperConfig.NetworkConfig private config;

    // Usuários
    address private owner;
    address private user1;
    address private user2;
    address private nonOwner;

    // Dados de Teste
    string private constant USER1_NAME = "User One";
    string private constant USER2_NAME = "User Two";
    bytes32 private constant USER1_HASH = keccak256(abi.encodePacked("user1_hash"));
    bytes32 private constant USER2_HASH = keccak256(abi.encodePacked("user2_hash"));

    function setUp() public {
        deployer = new DeployChainMedDPS();
        (userRegistry, dpsManager, chainMedAutomation, medicalAssetToken, config) = deployer.run();

        owner = config.account;
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        nonOwner = makeAddr("nonOwner");
    }

    // ////////////////////////////////////
    // Testes de Registro de Usuário   //
    // ////////////////////////////////////

    function testRegisterUserSuccess() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit UserRegistry.UserRegistered(user1, USER1_HASH, USER1_NAME, block.timestamp);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);

        // Verifica se o usuário foi registrado corretamente
        UserRegistry.User memory registeredUser = userRegistry.getUser(user1);
        assertEq(registeredUser.name, USER1_NAME);
        assertEq(registeredUser.userHash, USER1_HASH);
        assertTrue(registeredUser.active);
        assertEq(userRegistry.getUserCount(), 1);
        assertEq(userRegistry.getUserList()[0], user1);
        assertTrue(userRegistry.isUserActive(user1));
        assertEq(userRegistry.getUserAddressByHash(USER1_HASH), user1);
    }

    function testRevertIfRegisterUserNameIsEmpty() public {
        vm.prank(user1);
        vm.expectRevert(UserRegistry.UserRegistry__NameCannotBeEmpty.selector);
        userRegistry.registerUser("", USER1_HASH);
    }

    function testRevertIfRegisterUserAlreadyRegistered() public {
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);

        vm.prank(user1);
        vm.expectRevert(UserRegistry.UserRegistry__UserAlreadyRegistered.selector);
        userRegistry.registerUser("Another Name", USER2_HASH);
    }

    function testRevertIfRegisterUserHashAlreadyUsed() public {
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);

        vm.prank(user2);
        vm.expectRevert(UserRegistry.UserRegistry__HashAlreadyUsed.selector);
        userRegistry.registerUser(USER2_NAME, USER1_HASH);
    }

    // ////////////////////////////////////
    // Testes de Funções de Gerenciamento //
    // ////////////////////////////////////

    function testSetDPSManagerContractSuccess() public {
        // O setup já define o contrato, então precisamos de uma nova instância para testar
        UserRegistry newRegistry =
            new UserRegistry(config.callbackGasLimit, config.functionsRouter, config.subscriptionId, config.donId);
        address dpsManagerAddress = address(dpsManager);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit UserRegistry.DPSManagerContractSet(dpsManagerAddress);
        newRegistry.setDPSManagerContract(dpsManagerAddress);
    }

    function testRevertIfSetDPSManagerAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert(UserRegistry.UserRegistry__DPSManagerAlreadySet.selector);
        userRegistry.setDPSManagerContract(address(0x123));
    }

    function testRevertIfSetDPSManagerToZeroAddress() public {
        UserRegistry newRegistry =
            new UserRegistry(config.callbackGasLimit, config.functionsRouter, config.subscriptionId, config.donId);
        vm.prank(address(this));
        vm.expectRevert(UserRegistry.UserRegistry__InvalidAddress.selector);
        newRegistry.setDPSManagerContract(address(0));
    }

    function testSetAutomationContractSuccess() public {
        UserRegistry newRegistry =
            new UserRegistry(config.callbackGasLimit, config.functionsRouter, config.subscriptionId, config.donId);
        address automationAddress = address(chainMedAutomation);

        vm.prank(address(this));
        vm.expectEmit(true, true, true, true);
        emit UserRegistry.AutomationContractSet(automationAddress);
        newRegistry.setAutomationContract(automationAddress);
    }

    function testRevertIfSetAutomationAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert(UserRegistry.UserRegistry__AutomationAlreadySet.selector);
        userRegistry.setAutomationContract(address(0x123));
    }

    // ////////////////////////////////////
    // Testes de Desativação de Usuário  //
    // ////////////////////////////////////

    function testDeactivateUserSuccess() public {
        // Registra o usuário primeiro
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);
        assertTrue(userRegistry.isUserActive(user1));

        // Apenas o contrato de automação pode desativar
        vm.prank(address(chainMedAutomation));
        vm.expectEmit(true, true, true, true);
        emit UserRegistry.UserDeactivated(user1);
        userRegistry.deactivateUser(user1);

        assertFalse(userRegistry.isUserActive(user1));
    }

    function testRevertIfDeactivateUserNotAutomationContract() public {
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);

        // Tenta desativar com uma conta que não é o contrato de automação
        vm.prank(nonOwner);
        vm.expectRevert(UserRegistry.UserRegistry__CallerNotAutomation.selector);
        userRegistry.deactivateUser(user1);
    }

    // ////////////////////////////////////
    // Testes de Funções de Visualização //
    // ////////////////////////////////////

    function testGettersReturnCorrectValues() public {
        // Estado inicial
        assertEq(userRegistry.getUserCount(), 0);
        assertEq(userRegistry.getUserList().length, 0);

        // Registra user1
        vm.prank(user1);
        userRegistry.registerUser(USER1_NAME, USER1_HASH);

        // Verifica estado após registro de user1
        assertEq(userRegistry.getUserCount(), 1);
        assertEq(userRegistry.getUserList().length, 1);
        assertEq(userRegistry.getUserList()[0], user1);
        assertEq(userRegistry.getUserHash(user1), USER1_HASH);

        // Registra user2
        vm.prank(user2);
        userRegistry.registerUser(USER2_NAME, USER2_HASH);

        // Verifica estado após registro de user2
        assertEq(userRegistry.getUserCount(), 2);
        assertEq(userRegistry.getUserList().length, 2);
        assertEq(userRegistry.getUserList()[1], user2);
    }

    function testRevertIfGetUserForUnregisteredUser() public {
        vm.expectRevert(UserRegistry.UserRegistry__InvalidUserAddress.selector);
        userRegistry.getUser(user1);
    }
}
