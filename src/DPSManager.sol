// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UserRegistry} from "./UserRegistry.sol";
import {MedicalAssetToken} from "./MedicalAssetToken.sol";

/**
 * @title DPSManager
 * @author ChainMed Team
 * @notice Manages the creation and querying of Data Privacy Statements (DPS).
 * @dev This contract is responsible for storing the on-chain data related to a real-world asset (DPS).
 *      It orchestrates the process by first registering the data and then calling the MedicalAssetToken
 *      contract to mint the corresponding non-transferable token (NFT).
 */
contract DPSManager is ReentrancyGuard, Ownable {
    // Custom Errors
    error DPSManager__UserNotActive();
    error DPSManager__InsuranceNotAuthorized();
    error DPSManager__DPSNotFound();
    error DPSManager__UserNotFound();
    error DPSManager__InvalidAddress();
    error DPSManager__MedicalAssetTokenAlreadySet();
    error DPSManager__MedicalAssetTokenNotSet();

    // Structs
    /**
     * @notice Represents the on-chain data record for a DPS.
     * @dev Each DPS record is permanent and cannot be deactivated to ensure a complete historical log for insurance queries.
     * @param hashDPS The keccak256 hash of the off-chain DPS document.
     * @param dependentHashes An array of unique keccak256 hashes for dependents included in the DPS.
     * @param responsibleHash The unique keccak256 hash of the primary responsible user.
     * @param registeredAt The timestamp of the registration.
     */
    struct DPS {
        bytes32 hashDPS;
        bytes32[] dependentHashes;
        bytes32 responsibleHash;
        uint256 registeredAt;
    }

    // State Variables
    UserRegistry private immutable i_userRegistry;
    MedicalAssetToken private s_medicalAssetToken;
    uint256 private s_dpsCounter;
    mapping(uint256 => DPS) private s_dpsRegistry;
    mapping(bytes32 => uint256[]) private s_userHashToDPS;

    // Events
    event DPSRegistered(
        uint256 indexed dpsId, address indexed responsible, bytes32 indexed hashDPS, string dataDPS, uint256 timestamp
    );
    event DPSQueried(bytes32 indexed userHash, uint256 dpsCount);
    event MedicalAssetTokenSet(address indexed medicalAssetTokenAddress);

    /**
     * @notice Modifier to ensure the caller is an active user in the UserRegistry.
     */
    modifier onlyActiveUser() {
        if (!i_userRegistry.isUserActive(msg.sender)) revert DPSManager__UserNotActive();
        _;
    }

    /**
     * @notice Modifier to ensure the caller is an authorized insurance company in the UserRegistry.
     */
    modifier onlyAuthorizedInsurance() {
        if (!i_userRegistry.isInsuranceAuthorized(msg.sender)) revert DPSManager__InsuranceNotAuthorized();
        _;
    }

    /**
     * @notice Initializes the contract with the UserRegistry address.
     * @param _userRegistryAddress The address of the deployed UserRegistry contract.
     */
    constructor(address _userRegistryAddress) Ownable(msg.sender) {
        i_userRegistry = UserRegistry(_userRegistryAddress);
    }

    /**
     * @notice Registers a new DPS record and triggers the minting of its corresponding token.
     * @dev The caller must be an active user. This function stores DPS data on-chain and then
     *      calls `safeMint` on the MedicalAssetToken contract. All registered DPS are considered permanent and queriable.
     * @param hashDPS A keccak256 hash of the off-chain DPS document.
     * @param responsibleHash The unique keccak256 hash of the responsible user (the caller).
     * @param dependentHashes An array of unique keccak256 hashes for any dependents.
     * @param dataDPS The Base64 encoded JSON string representing the token's metadata.
     */
    function registerDPS(
        bytes32 hashDPS,
        bytes32 responsibleHash,
        bytes32[] calldata dependentHashes,
        string calldata dataDPS
    ) external nonReentrant onlyActiveUser {
        if (address(s_medicalAssetToken) == address(0)) revert DPSManager__MedicalAssetTokenNotSet();
        uint256 dpsId = s_dpsCounter;
        s_dpsCounter++;

        s_dpsRegistry[dpsId] = DPS({
            responsibleHash: responsibleHash,
            dependentHashes: dependentHashes,
            hashDPS: hashDPS,
            registeredAt: block.timestamp
        });

        s_userHashToDPS[responsibleHash].push(dpsId);
        for (uint256 i = 0; i < dependentHashes.length; i++) {
            s_userHashToDPS[dependentHashes[i]].push(dpsId);
        }

        s_medicalAssetToken.safeMint(msg.sender, hashDPS, dataDPS);

        emit DPSRegistered({
            dpsId: dpsId,
            responsible: msg.sender,
            hashDPS: hashDPS,
            dataDPS: dataDPS,
            timestamp: block.timestamp
        });
    }

    /**
     * @notice Sets the MedicalAssetToken contract address.
     * @dev This can only be called once by the owner and is required before any DPS can be registered.
     * @param _medicalAssetTokenAddress The address of the deployed MedicalAssetToken contract.
     */
    function setMedicalAssetToken(address _medicalAssetTokenAddress) external nonReentrant onlyOwner {
        if (address(s_medicalAssetToken) != address(0)) revert DPSManager__MedicalAssetTokenAlreadySet();
        if (_medicalAssetTokenAddress == address(0)) revert DPSManager__InvalidAddress();
        s_medicalAssetToken = MedicalAssetToken(_medicalAssetTokenAddress);
        emit MedicalAssetTokenSet(_medicalAssetTokenAddress);
    }

    // --- View Functions ---

    /**
     * @notice Allows an authorized insurance company to query for all DPS records associated with a user hash.
     * @dev Returns all historical DPS records for the user, as they are permanent and always queriable by design.
     * @param _userHash The unique keccak256 hash of the user (responsible or dependent) to query.
     * @return dpsRecords An array of all associated DPS structs.
     * @return dpsDatas An array of corresponding token URIs (Base64 data).
     */
    function queryDPS(bytes32 _userHash)
        external
        view
        onlyAuthorizedInsurance
        returns (DPS[] memory, string[] memory)
    {
        if (!_checkUserIsActive(_userHash)) revert DPSManager__UserNotActive();
        uint256[] storage dpsIds = s_userHashToDPS[_userHash];
        uint256 dpsCount = dpsIds.length;
        if (dpsCount == 0) return (new DPS[](0), new string[](0));

        DPS[] memory dpsRecords = new DPS[](dpsCount);
        string[] memory dpsDatas = new string[](dpsCount);
        for (uint256 i = 0; i < dpsCount; i++) {
            DPS storage dps = s_dpsRegistry[dpsIds[i]];
            dpsRecords[i] = dps;
            dpsDatas[i] = _getTokenDataFromHash(dps.hashDPS);
        }

        return (dpsRecords, dpsDatas);
    }

    /**
     * @notice Returns the total number of DPS records ever registered.
     * @return The total count of DPS records.
     */
    function getDPSCount() external view returns (uint256) {
        return s_dpsCounter;
    }

    /**
     * @notice Returns the number of DPS records associated with a specific user hash.
     * @param _userHash The user's keccak256 hash to query.
     * @return The number of associated DPS records.
     */
    function getUserDPSCount(bytes32 _userHash) external view returns (uint256) {
        return s_userHashToDPS[_userHash].length;
    }

    /**
     * @notice Retrieves the on-chain data for a specific DPS record.
     * @dev This is a view function that provides direct access to the DPS struct stored in the registry.
     *      It does not return the off-chain data (tokenURI), only the on-chain metadata.
     * @param _dpsId The unique identifier of the DPS record to retrieve.
     * @return The DPS struct containing the on-chain data.
     */
    function getDPSInfo(uint256 _dpsId) external view returns (DPS memory) {
        if (_dpsId >= s_dpsCounter) revert DPSManager__DPSNotFound();
        DPS memory dps = s_dpsRegistry[_dpsId];
        return dps;
    }

    /**
     * @notice Internal function to retrieve the token URI for a given DPS hash.
     * @dev Encapsulates the interaction with the MedicalAssetToken contract for fetching token data.
     * @param _hashDPS The keccak256 hash of the DPS document linked to the token.
     * @return The token URI string.
     */
    function _getTokenDataFromHash(bytes32 _hashDPS) internal view returns (string memory) {
        uint256 tokenId = s_medicalAssetToken.getTokenIdByHash(_hashDPS);
        return s_medicalAssetToken.tokenURI(tokenId);
    }

    /**
     * @notice Internal function to check if a user, identified by hash, is active.
     * @dev Interacts with the UserRegistry to verify the user's status.
     * @param _userHash The keccak256 hash of the user to check.
     * @return True if the user is active, false otherwise.
     */
    function _checkUserIsActive(bytes32 _userHash) internal view returns (bool) {
        address userAddress = i_userRegistry.getUserAddressByHash(_userHash);
        if (userAddress == address(0)) revert DPSManager__UserNotFound();
        return i_userRegistry.isUserActive(userAddress);
    }
}
