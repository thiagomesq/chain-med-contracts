// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserRegistry} from "./UserRegistry.sol";
import {DPSManager} from "./DPSManager.sol";
import {PrescriptionManager} from "./PrescriptionManager.sol";

/**
 * @title ChainMedAutomation
 * @author ChainMed Team
 * @notice A Chainlink Automation compatible contract for system maintenance.
 * @dev This contract periodically checks for and deactivates stale users and invalidates expired prescriptions.
 *      It uses a batch processing pattern to ensure scalability.
 */
contract ChainMedAutomation is AutomationCompatibleInterface, Ownable {
    // Custom Errors
    error ChainMedAutomation__NoUpkeepNeeded();
    error ChainMedAutomation__InactivePeriodCannotBeZero();
    error ChainMedAutomation__BatchSizeCannotBeZero();
    error ChainMedAutomation__InvalidForwarderAddress();

    // State Variables
    UserRegistry private immutable i_userRegistry;
    DPSManager private immutable i_dpsManager;
    PrescriptionManager private immutable i_prescriptionManager;

    /// @notice The period after which an active user with no DPS records is considered inactive.
    uint256 private constant INITIAL_USER_INACTIVE_PERIOD = 30 days;
    uint256 private constant INITIAL_USER_BATCH_SIZE = 20;
    uint256 private constant INITIAL_PRESCRIPTION_BATCH_SIZE = 20;

    uint256 private s_userinactivePeriod;
    uint256 private s_lastCheckedUserIndex;
    uint256 private s_userBatchSize;
    uint256 private s_lastCheckedPrescriptionIndex;
    uint256 private s_prescriptionBatchSize;
    address private s_automationForwarder;

    // Events
    event UserInactivePeriodSet(uint256 indexed newPeriod);
    event UserDeactivated(address indexed user);
    event PrescriptionInvalidated(uint256 indexed prescriptionId);
    event UserBatchSizeSet(uint256 indexed newSize);
    event PrescriptionBatchSizeSet(uint256 indexed newSize);
    event AutomationForwarderSet(address indexed forwarder);

    /**
     * @notice Initializes the contract with the addresses of the core system contracts.
     * @param _userRegistryAddress The address of the deployed UserRegistry contract.
     * @param _dpsManagerAddress The address of the deployed DPSManager contract.
     * @param _prescriptionManagerAddress The address of the deployed PrescriptionManager contract.
     */
    constructor(address _userRegistryAddress, address _dpsManagerAddress, address _prescriptionManagerAddress)
        Ownable(msg.sender)
    {
        i_userRegistry = UserRegistry(_userRegistryAddress);
        i_dpsManager = DPSManager(_dpsManagerAddress);
        i_prescriptionManager = PrescriptionManager(_prescriptionManagerAddress);
        s_userinactivePeriod = INITIAL_USER_INACTIVE_PERIOD;
        s_userBatchSize = INITIAL_USER_BATCH_SIZE;
        s_prescriptionBatchSize = INITIAL_PRESCRIPTION_BATCH_SIZE; // <-- INICIALIZAR
        emit UserInactivePeriodSet(INITIAL_USER_INACTIVE_PERIOD);
        emit UserBatchSizeSet(INITIAL_USER_BATCH_SIZE);
        emit PrescriptionBatchSizeSet(INITIAL_PRESCRIPTION_BATCH_SIZE); // <-- EMITIR EVENTO
    }

    // --- Configuration Functions ---

    /**
     * @notice Sets the period after which an active user with no DPS records is considered inactive.
     * @dev Can only be called by the contract owner. Period must be greater than zero.
     * @param _newPeriod The new inactive period in seconds.
     */
    function setUserInactivePeriod(uint256 _newPeriod) external onlyOwner {
        if (_newPeriod == 0) revert ChainMedAutomation__InactivePeriodCannotBeZero();
        s_userinactivePeriod = _newPeriod;
        emit UserInactivePeriodSet(_newPeriod);
    }

    /**
     * @notice Sets the number of users to check in each `checkUpkeep` run.
     * @dev Can only be called by the contract owner. Size cannot be zero.
     * @param _newSize The new batch size for user processing.
     */
    function setUserBatchSize(uint256 _newSize) external onlyOwner {
        if (_newSize == 0) revert ChainMedAutomation__BatchSizeCannotBeZero();
        s_userBatchSize = _newSize;
        emit UserBatchSizeSet(_newSize);
    }

    /**
     * @notice Sets the address of the automation forwarder.
     * @dev This address is used to forward automation tasks. Can only be called by the owner.
     * @param _forwarder The address of the automation forwarder.
     */
    function setAutomationForwarder(address _forwarder) external onlyOwner {
        if (_forwarder == address(0)) revert ChainMedAutomation__InvalidForwarderAddress();
        if (_forwarder == s_automationForwarder) return; // No change
        s_automationForwarder = _forwarder;
        emit AutomationForwarderSet(_forwarder);
    }

    /**
     * @notice Sets the number of prescriptions to check in each `checkUpkeep` run.
     * @dev Can only be called by the contract owner. Size cannot be zero.
     * @param _newSize The new batch size for prescription processing.
     */
    function setPrescriptionBatchSize(uint256 _newSize) external onlyOwner {
        if (_newSize == 0) revert ChainMedAutomation__BatchSizeCannotBeZero();
        s_prescriptionBatchSize = _newSize;
        emit PrescriptionBatchSizeSet(_newSize);
    }

    // --- Automation Functions ---

    /**
     * @notice Checks if maintenance (upkeep) is required.
     * @dev This function is called by Chainlink Automation nodes. It uses a scalable batch processing
     *      pattern to check for stale users (active for over a year without registering any DPS).
     *      If any stale users are found, it encodes them into `performData` for deactivation.
     * @return upkeepNeeded A boolean indicating if `performUpkeep` should be called.
     * @return performData The ABI-encoded data (an array of user addresses) to be passed to `performUpkeep`.
     */
    function checkUpkeep(bytes memory) external view override returns (bool upkeepNeeded, bytes memory performData) {
        // Processa um lote de usuários
        uint256 userCount = i_userRegistry.getUserCount();
        if (userCount == 0) {
            upkeepNeeded = false;
            performData = bytes("");
            return (upkeepNeeded, performData);
        }
        uint256 userEnd = s_lastCheckedUserIndex + s_userBatchSize;
        if (userEnd > userCount) {
            userEnd = userCount;
        }
        address[] memory users = i_userRegistry.getUserList();
        address[] memory usersToDeactivate = new address[](userCount);
        uint256 usersToDeactivateCount = 0;
        for (uint256 i = s_lastCheckedUserIndex; i < userEnd; i++) {
            address userAddress = users[i];
            UserRegistry.User memory user = i_userRegistry.getUser(userAddress);

            uint256 userDPSCount = i_dpsManager.getUserDPSCount(user.userHash);
            if (userDPSCount == 0 && (block.timestamp - user.registrationDate) > INITIAL_USER_INACTIVE_PERIOD) {
                usersToDeactivate[usersToDeactivateCount] = userAddress;
                usersToDeactivateCount++;
            }
        }

        // --- NOVA LÓGICA DE PRESCRIÇÕES ---
        uint256[] memory activePrescriptionIds = i_prescriptionManager.getActivePrescriptionIds();
        uint256 prescriptionCount = activePrescriptionIds.length;
        uint256 prescriptionEnd = s_lastCheckedPrescriptionIndex + s_prescriptionBatchSize;
        if (prescriptionEnd > prescriptionCount) {
            prescriptionEnd = prescriptionCount;
        }

        uint256[] memory prescriptionsToInvalidate = new uint256[](prescriptionCount);
        uint256 prescriptionsToInvalidateCount = 0;

        for (uint256 i = s_lastCheckedPrescriptionIndex; i < prescriptionEnd; i++) {
            uint256 pId = activePrescriptionIds[i];
            PrescriptionManager.Prescription memory p = i_prescriptionManager.getPrescriptionDetails(pId);
            if (p.status == PrescriptionManager.PrescriptionStatus.Valid && block.timestamp > p.dueDate) {
                prescriptionsToInvalidate[prescriptionsToInvalidateCount] = pId;
                prescriptionsToInvalidateCount++;
            }
        }

        // --- COMBINAR RESULTADOS ---
        if (usersToDeactivateCount > 0 || prescriptionsToInvalidateCount > 0) {
            upkeepNeeded = true;
            assembly {
                mstore(usersToDeactivate, usersToDeactivateCount)
                mstore(prescriptionsToInvalidate, prescriptionsToInvalidateCount)
            }
            performData = abi.encode(usersToDeactivate, prescriptionsToInvalidate);
        } else {
            upkeepNeeded = false;
            performData = bytes("");
        }
    }

    /**
     * @notice Executes the maintenance tasks identified in `checkUpkeep`.
     * @dev This function is called by a Chainlink Automation node only if `checkUpkeep` returns true.
     *      It decodes the `performData` and calls the deactivation function for each stale user.
     *      Finally, it updates the internal index to ensure the next `checkUpkeep` run continues from where this one left off.
     * @param performData The ABI-encoded data from `checkUpkeep`.
     */
    function performUpkeep(bytes calldata performData) external override {
        if (msg.sender != s_automationForwarder) {
            revert ChainMedAutomation__InvalidForwarderAddress();
        }
        (address[] memory usersToDeactivate, uint256[] memory prescriptionsToInvalidate) =
            abi.decode(performData, (address[], uint256[]));

        // --- LÓGICA DE USUÁRIOS (EXISTENTE) ---
        for (uint256 i = 0; i < usersToDeactivate.length; i++) {
            address userAddress = usersToDeactivate[i];
            i_userRegistry.deactivateUser(userAddress);
            emit UserDeactivated(userAddress);
        }

        // --- NOVA LÓGICA DE PRESCRIÇÕES ---
        for (uint256 i = 0; i < prescriptionsToInvalidate.length; i++) {
            uint256 pId = prescriptionsToInvalidate[i];
            i_prescriptionManager.invalidatePrescription(pId);
            emit PrescriptionInvalidated(pId);
        }

        // --- ATUALIZAR ÍNDICES ---
        uint256 userCount = i_userRegistry.getUserCount();
        if (userCount == 0) {
            s_lastCheckedUserIndex = 0; // Reset index if no users left
        } else {
            s_lastCheckedUserIndex = (s_lastCheckedUserIndex + s_userBatchSize) % userCount;
        }
        uint256 prescriptionCount = i_prescriptionManager.getActivePrescriptionIds().length;
        if (prescriptionCount == 0) {
            s_lastCheckedPrescriptionIndex = 0;
        } else {
            s_lastCheckedPrescriptionIndex =
                (s_lastCheckedPrescriptionIndex + s_prescriptionBatchSize) % prescriptionCount;
        }
    }

    // --- View Functions ---
    function getUserInactivePeriod() external view onlyOwner returns (uint256) {
        return s_userinactivePeriod;
    }

    function getUserBatchSize() external view onlyOwner returns (uint256) {
        return s_userBatchSize;
    }

    function getPrescriptionBatchSize() external view onlyOwner returns (uint256) {
        return s_prescriptionBatchSize;
    }
}
