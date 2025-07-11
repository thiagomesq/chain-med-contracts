// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserRegistry} from "./UserRegistry.sol";
import {DPSManager} from "./DPSManager.sol";

/**
 * @title ChainMedAutomation
 * @author ChainMed Team
 * @notice A Chainlink Automation compatible contract for system maintenance.
 * @dev This contract periodically checks for and deactivates stale users (e.g., users registered for a long time
 *      with no activity) to maintain system health. It uses a batch processing pattern to ensure scalability.
 */
contract ChainMedAutomation is AutomationCompatibleInterface, Ownable {
    // Custom Errors
    error ChainMedAutomation__NoUpkeepNeeded();
    error ChainMedAutomation__BatchSizeCannotBeZero();
    error ChainMedAutomation__InvalidForwarderAddress();

    // State Variables
    UserRegistry public immutable i_userRegistry;
    DPSManager public immutable i_dpsManager;

    /// @notice The period after which an active user with no DPS records is considered inactive.
    uint256 private constant USER_INACTIVE_PERIOD = 365 days;

    uint256 private s_lastCheckedUserIndex;
    uint256 public s_userBatchSize;
    address public s_automationForwarder;

    // Events
    event UserDeactivated(address indexed user);
    event UserBatchSizeSet(uint256 indexed newSize);
    event AutomationForwarderSet(address indexed forwarder);

    /**
     * @notice Initializes the contract with the addresses of the core system contracts.
     * @param _userRegistryAddress The address of the deployed UserRegistry contract.
     * @param _dpsManagerAddress The address of the deployed DPSManager contract.
     */
    constructor(address _userRegistryAddress, address _dpsManagerAddress) Ownable(msg.sender) {
        i_userRegistry = UserRegistry(_userRegistryAddress);
        i_dpsManager = DPSManager(_dpsManagerAddress);
        s_userBatchSize = 20;
        emit UserBatchSizeSet(20);
    }

    // --- Configuration Functions ---

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
            if (user.active && userDPSCount == 0 && (block.timestamp - user.registrationDate) > USER_INACTIVE_PERIOD) {
                usersToDeactivate[usersToDeactivateCount] = userAddress;
                usersToDeactivateCount++;
            }
        }

        if (usersToDeactivateCount > 0) {
            upkeepNeeded = true;

            assembly {
                mstore(usersToDeactivate, usersToDeactivateCount)
            }

            performData = abi.encode(usersToDeactivate);
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
        (address[] memory usersToDeactivate) = abi.decode(performData, (address[]));

        if (usersToDeactivate.length == 0) {
            revert ChainMedAutomation__NoUpkeepNeeded();
        }

        for (uint256 i = 0; i < usersToDeactivate.length; i++) {
            address userAddress = usersToDeactivate[i];
            i_userRegistry.deactivateUser(userAddress);
            emit UserDeactivated(userAddress);
        }

        uint256 userCount = i_userRegistry.getUserCount();
        if (userCount == 0) {
            s_lastCheckedUserIndex = 0; // Reset index if no users left
        } else {
            s_lastCheckedUserIndex = (s_lastCheckedUserIndex + s_userBatchSize) % userCount;
        }
    }
}
