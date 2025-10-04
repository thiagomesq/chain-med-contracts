// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * @title UserRegistry
 * @author ChainMed Team
 * @notice Manages the identity and status of users and insurance companies within the ChainMed ecosystem.
 * @dev This contract serves as the central authority for user registration (KYC/identity) and insurance authorization.
 *      It uses Chainlink Functions to verify insurance credentials off-chain.
 */
contract UserRegistry is Ownable, FunctionsClient, ReentrancyGuard {
    using FunctionsRequest for FunctionsRequest.Request;

    // Custom Errors
    error UserRegistry__NameCannotBeEmpty();
    error UserRegistry__UserAlreadyRegistered();
    error UserRegistry__HashAlreadyUsed();
    error UserRegistry__InsuranceAlreadyAuthorized();
    error UserRegistry__InvalidAddress();
    error UserRegistry__InvalidUserAddress();
    error UserRegistry__InvalidInsuranceAddress();
    error UserRegistry__DPSManagerAlreadySet();
    error UserRegistry__DPSManagerNotSet();
    error UserRegistry__CallerNotDPSManager();
    error UserRegistry__AutomationNotSet();
    error UserRegistry__CallerNotAutomation();

    // Structs
    /**
     * @notice Represents a registered user in the system.
     * @param name The user's name.
     * @param userHash A unique keccak256 hash identifying the user.
     * @param active The current status of the user.
     * @param registrationDate The timestamp of the user's registration.
     */
    struct User {
        string name;
        bytes32 userHash;
        bool active;
        uint256 registrationDate;
    }

    /**
     * @notice Represents an authorized insurance company.
     * @param name The insurance company's name.
     * @param cnpj The company's unique identifier (CNPJ).
     * @param authorized The authorization status.
     * @param registrationDate The timestamp of the authorization.
     */
    struct Insurance {
        string name;
        string cnpj;
        bool authorized;
        uint256 registrationDate;
    }

    /**
     * @notice Stores details of a pending insurance authorization request.
     */
    struct PendingInsuranceAuthorization {
        address insuranceAddress;
        string name;
        string cnpj;
    }

    /**
     * @notice Defines the type of an off-chain request made via Chainlink Functions.
     */
    enum RequestType {
        NONE,
        INSURANCE_AUTHORIZATION
    }

    // State Variables
    address private s_dpsManagerContract; // Endereço do contrato DPSManager
    address private s_automationContract; // Endereço do contrato Automation
    mapping(address => User) private s_users;
    mapping(address => Insurance) private s_insurances;
    mapping(bytes32 => address) private s_userHashToAddress;
    address[] private s_usersList;
    address[] private s_insurancesList;

    // Chainlink Functions
    uint32 private immutable i_callbackGasLimit; // Limite de gás para callbacks
    bytes32 private immutable i_donId; // DON ID do Chainlink Functions
    uint64 private immutable i_subscriptionId; // Subscription ID para Chainlink Functions
    bytes private lastResponse;
    bytes private lastError;
    mapping(bytes32 => RequestType) private requestTypes;
    mapping(bytes32 => PendingInsuranceAuthorization) private insuranceAuthRequests;

    // Events
    event UserRegistered(address indexed userAddress, bytes32 indexed userHash, string name, uint256 timestamp);
    event InsuranceAuthorized(address indexed insurance, string name, string cnpj, uint256 timestamp);
    event InsuranceVerificationRequested(bytes32 indexed requestId, address insurance, string cnpj);
    event UserDeactivated(address indexed user);
    event QueryPerformed(address indexed insurance, address indexed queriedUser, string queryType);
    event DPSManagerContractSet(address indexed dpsManagerAddress);
    event AutomationContractSet(address indexed automationAddress);

    /**
     * @notice Modifier to ensure a function is called only by the registered DPSManager contract.
     */
    modifier onlyDPSManager() {
        if (s_dpsManagerContract == address(0)) revert UserRegistry__DPSManagerNotSet();
        if (msg.sender != s_dpsManagerContract) revert UserRegistry__CallerNotDPSManager();
        _;
    }

    /**
     * @notice Modifier to ensure a function is called only by the registered Automation contract.
     */
    modifier onlyAutomation() {
        if (s_automationContract == address(0)) revert UserRegistry__AutomationNotSet();
        if (msg.sender != s_automationContract) revert UserRegistry__CallerNotAutomation();
        _;
    }

    /**
     * @notice Initializes the contract with Chainlink Functions configuration.
     * @param _callbackGasLimit The gas limit for the Chainlink Functions callback.
     * @param _functionsRouter The address of the Chainlink Functions router.
     * @param _subscriptionId The ID of the Chainlink Functions subscription.
     */
    constructor(uint32 _callbackGasLimit, address _functionsRouter, uint64 _subscriptionId, bytes32 _donId)
        Ownable(msg.sender)
        FunctionsClient(_functionsRouter)
    {
        i_callbackGasLimit = _callbackGasLimit;
        i_subscriptionId = _subscriptionId;
        i_donId = _donId;
    }

    // --- User Registration ---
    /**
     * @notice Registers a new user in the system.
     * @dev The caller's address becomes the primary identifier. The user hash must be unique.
     * @param _name The name of the user.
     * @param _userHash A unique keccak256 hash representing the user.
     */
    function registerUser(string calldata _name, bytes32 _userHash) external nonReentrant {
        if (bytes(_name).length == 0) revert UserRegistry__NameCannotBeEmpty();
        if (s_users[msg.sender].active) revert UserRegistry__UserAlreadyRegistered();
        if (s_userHashToAddress[_userHash] != address(0)) revert UserRegistry__HashAlreadyUsed();

        s_users[msg.sender] = User({name: _name, userHash: _userHash, active: true, registrationDate: block.timestamp});
        s_userHashToAddress[_userHash] = msg.sender;
        s_usersList.push(msg.sender);
        emit UserRegistered(msg.sender, _userHash, _name, block.timestamp);
    }

    // --- Chainlink Functions Logic ---

    /**
     * @notice Requests authorization for an insurance company by verifying its CNPJ off-chain.
     * @dev Creates and sends a Chainlink Functions request. The result is handled by `fulfillRequest`.
     * @param _name The name of the insurance company.
     * @param _cnpj The CNPJ to be verified.
     * @param _source The JavaScript source code for the Chainlink Functions request.
     */
    function requestInsuranceAuthorization(string calldata _name, string calldata _cnpj, string calldata _source)
        external
        nonReentrant
    {
        if (bytes(_name).length == 0) revert UserRegistry__NameCannotBeEmpty();
        if (s_insurances[msg.sender].authorized) revert UserRegistry__InsuranceAlreadyAuthorized();

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(_source);
        string[] memory args = new string[](1);
        args[0] = _cnpj;
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subscriptionId, i_callbackGasLimit, i_donId);

        requestTypes[requestId] = RequestType.INSURANCE_AUTHORIZATION;
        insuranceAuthRequests[requestId] =
            PendingInsuranceAuthorization({insuranceAddress: msg.sender, name: _name, cnpj: _cnpj});
        emit InsuranceVerificationRequested(requestId, msg.sender, _cnpj);
    }

    /**
     * @notice Callback function for Chainlink Functions to fulfill requests.
     * @dev Handles the response from the off-chain execution.
     * @param _requestId The unique ID of the request.
     * @param _response The response data from the off-chain source.
     * @param _err Any error data.
     */
    function fulfillRequest(bytes32 _requestId, bytes memory _response, bytes memory _err) internal override {
        if (_err.length > 0) {
            lastError = _err;
        } else {
            lastResponse = _response;
            RequestType reqType = requestTypes[_requestId];
            if (abi.decode(_response, (bool))) {
                if (reqType == RequestType.INSURANCE_AUTHORIZATION) _completeInsuranceAuthorization(_requestId);
            }
        }
        delete requestTypes[_requestId];
        delete insuranceAuthRequests[_requestId];
    }

    /**
     * @notice Internal function to complete the insurance authorization process.
     * @dev Called by `fulfillRequest` upon a successful off-chain verification.
     * @param _requestId The ID of the pending request.
     */
    function _completeInsuranceAuthorization(bytes32 _requestId) private {
        PendingInsuranceAuthorization memory p = insuranceAuthRequests[_requestId];
        s_insurances[p.insuranceAddress] =
            Insurance({name: p.name, cnpj: p.cnpj, authorized: true, registrationDate: block.timestamp});
        s_insurancesList.push(p.insuranceAddress);
        emit InsuranceAuthorized(p.insuranceAddress, p.name, p.cnpj, block.timestamp);
    }

    // --- Management Functions (Owner only) ---

    /**
     * @notice Sets the address of the DPSManager contract.
     * @dev Can only be called once by the owner. Essential for inter-contract communication.
     * @param _dpsManagerAddress The address of the deployed DPSManager contract.
     */
    function setDPSManagerContract(address _dpsManagerAddress) external nonReentrant onlyOwner {
        if (s_dpsManagerContract != address(0)) revert UserRegistry__DPSManagerAlreadySet();
        if (_dpsManagerAddress == address(0)) revert UserRegistry__InvalidAddress();
        s_dpsManagerContract = _dpsManagerAddress;
        emit DPSManagerContractSet(_dpsManagerAddress);
    }

    /**
     * @notice Sets the address of the Automation contract.
     * @dev Can only be called once by the owner.
     * @param _automationAddress The address of the deployed Automation contract.
     */
    function setAutomationContract(address _automationAddress) external nonReentrant onlyOwner {
        if (_automationAddress == address(0)) revert UserRegistry__InvalidAddress();
        s_automationContract = _automationAddress;
        emit AutomationContractSet(_automationAddress);
    }

    // --- External/Public Functions ---

    /**
     * @notice Deactivates a user's account.
     * @dev Can only be called by the authorized Automation contract.
     * @param _userAddress The address of the user to deactivate.
     */
    function deactivateUser(address _userAddress) external onlyAutomation {
        s_users[_userAddress].active = false;
        emit UserDeactivated(_userAddress);
    }

    // --- View Functions ---

    /**
     * @notice Checks if a user is currently active.
     * @param _user The address of the user to check.
     * @return True if the user is active, false otherwise.
     */
    function isUserActive(address _user) external view returns (bool) {
        return s_users[_user].active;
    }

    /**
     * @notice Checks if an insurance company is authorized.
     * @param _insurance The address of the insurance company to check.
     * @return True if the company is authorized, false otherwise.
     */
    function isInsuranceAuthorized(address _insurance) external view returns (bool) {
        return s_insurances[_insurance].authorized;
    }

    /**
     * @notice Returns the list of active user addresses.
     * @return An array of user addresses.
     */
    function getUserList() external view returns (address[] memory) {
        uint256 userCount = getUserCount();
        address[] memory activeUsers = new address[](userCount);
        uint256 index = 0;
        uint256 totalUsers = s_usersList.length;
        for (uint256 i = 0; i < totalUsers; i++) {
            if (s_users[s_usersList[i]].active) {
                activeUsers[index] = s_usersList[i];
                index++;
            }
        }
        return activeUsers;
    }

    /**
     * @notice Returns the list of all authorized insurance addresses.
     * @return An array of insurance addresses.
     */
    function getInsuranceList() external view returns (address[] memory) {
        return s_insurancesList;
    }

    /**
     * @notice Returns the total number of authorized insurances.
     * @return The number of authorized insurances.
     */
    function getInsuranceCount() external view returns (uint256) {
        return s_insurancesList.length;
    }

    /**
     * @notice Retrieves the details of a specific user.
     * @param _user The address of the user.
     * @return The User struct containing user details.
     */
    function getUser(address _user) external view returns (User memory) {
        User memory user = s_users[_user];
        if (user.registrationDate == 0) revert UserRegistry__InvalidUserAddress();
        return user;
    }

    /**
     * @notice Retrieves the details of a specific insurance company.
     * @param _insurance The address of the insurance company.
     * @return The Insurance struct containing insurance details.
     */
    function getInsurance(address _insurance) external view returns (Insurance memory) {
        Insurance memory insurance = s_insurances[_insurance];
        if (insurance.registrationDate == 0) revert UserRegistry__InvalidInsuranceAddress();
        return insurance;
    }

    /**
     * @notice Retrieves the unique hash for a given user address.
     * @param _user The address of the user.
     * @return The user's unique keccak256 hash.
     */
    function getUserHash(address _user) external view returns (bytes32) {
        return s_users[_user].userHash;
    }

    /**
     * @notice Retrieves the address associated with a given user hash.
     * @param _userHash The unique keccak256 hash of the user.
     * @return The user's wallet address.
     */
    function getUserAddressByHash(bytes32 _userHash) external view returns (address) {
        address userAddress = s_userHashToAddress[_userHash];
        if (userAddress == address(0)) revert UserRegistry__InvalidAddress();
        return userAddress;
    }

    /**
     * @notice Returns the number of active users.
     * @dev Iterates through the user list and counts only the users marked as active.
     * @return The total count of active users.
     */
    function getUserCount() public view returns (uint256) {
        uint256 activeUserCount = 0;
        uint256 totalUsers = s_usersList.length;
        for (uint256 i = 0; i < totalUsers; i++) {
            if (s_users[s_usersList[i]].active) {
                activeUserCount++;
            }
        }
        return activeUserCount;
    }

    // --- Internal Helpers ---
    /**
     * @dev Converts bytes data to a keccak256 hash represented as a string.
     * @param data The bytes to hash.
     * @return The resulting hash as a string.
     */
    function _keccak256ToString(bytes calldata data) private pure returns (string memory) {
        return string(abi.encodePacked(keccak256(data)));
    }
}
