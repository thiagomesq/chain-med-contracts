// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserRegistry} from "./UserRegistry.sol";
import {DoctorRegistry} from "./DoctorRegistry.sol"; // <-- Importar o novo contrato
import {PrescriptionToken} from "./PrescriptionToken.sol";

/**
 * @title PrescriptionManager
 * @author ChainMed Team
 * @notice Manages the lifecycle (creation, sharing, invalidation) of medical prescriptions.
 * @dev Relies on DoctorRegistry for doctor verification and UserRegistry for patient verification.
 */
contract PrescriptionManager is Ownable {
    // Errors
    error PrescriptionManager__AutomationNotSet();
    error PrescriptionManager__CallerNotAutomation();
    error PrescriptionManager__InvalidAddress();
    error PrescriptionManager__OnlyDoctorsAuthorized();
    error PrescriptionManager__DoctorNotRegistered();
    error PrescriptionManager__PatientNotRegistered();
    error PrescriptionManager__NotAuthorizedToView();
    error PrescriptionManager__OnlyPatientCanShare();
    error PrescriptionManager__PrescriptionNotFound();
    error PrescriptionManager__AlreadyShared();

    // Type Definitions
    enum PrescriptionStatus {
        Valid,
        Expired,
        Used
    }

    /**
     * @notice Represents a medication in a prescription.
     * @dev This struct is used to store the details of each medication prescribed.
     * @param name The name of the medication.
     * @param dosage The prescribed dosage for the medication.
     * @param instructions The instructions for taking the medication.
     */
    struct Medication {
        string name;
        string dosage;
        string instructions;
    }

    /**
     * @notice Represents the core on-chain data for a medical prescription.
     * @dev This data is used for on-chain logic and authorization checks.
     *      The full details are in the off-chain tokenURI metadata.
     * @param doctor The address of the doctor who created the prescription.
     * @param patient The address of the patient who owns the prescription.
     * @param createdAt The timestamp of creation.
     */
    struct Prescription {
        address doctor;
        address patient;
        Medication[] medications;
        uint256 createdAt;
        uint256 dueDate;
        PrescriptionStatus status;
    }

    // State Variables
    UserRegistry private immutable i_userRegistry;
    DoctorRegistry private immutable i_doctorRegistry; // <-- Nova dependência
    PrescriptionToken private immutable i_prescriptionToken;

    address private s_automationContract;

    mapping(uint256 => Prescription) private s_prescriptions; // tokenId => Prescription data
    mapping(uint256 => mapping(address => bool)) private s_prescriptionShares; // tokenId => doctorAddress => hasAccess
    mapping(address => uint256[]) private s_doctorToCreatedPrescriptions;
    mapping(address => uint256[]) private s_doctorToSharedPrescriptions;

    // --- VARIÁVEIS PARA AUTOMAÇÃO ---
    uint256[] private s_activePrescriptionIds;
    mapping(uint256 => uint256) private s_idToIndexInActiveList;

    uint256 private s_prescriptionCounter;

    // Events
    event AutomationContractSet(address indexed automationAddress);
    event PrescriptionCreated(uint256 indexed prescriptionId, address indexed doctor, address indexed patient);
    event PrescriptionShared(uint256 indexed prescriptionId, address indexed sharedWith);
    event PrescriptionInvalidated(uint256 indexed prescriptionId);

    // Modifiers
    modifier onlyAutomation() {
        if (s_automationContract == address(0)) revert PrescriptionManager__AutomationNotSet();
        if (msg.sender != s_automationContract) revert PrescriptionManager__CallerNotAutomation();
        _;
    }

    modifier onlyDoctor() {
        // A lógica agora chama o novo contrato
        if (!i_doctorRegistry.isDoctorRegistered(msg.sender)) revert PrescriptionManager__OnlyDoctorsAuthorized();
        _;
    }

    /**
     * @notice Initializes the contract with its dependencies.
     * @param _userRegistryAddress The address of the UserRegistry contract.
     * @param _doctorRegistryAddress The address of the DoctorRegistry contract.
     * @param _prescriptionTokenAddress The address of the PrescriptionToken contract.
     */
    constructor(
        address _userRegistryAddress,
        address _doctorRegistryAddress, // <-- Novo parâmetro
        address _prescriptionTokenAddress
    ) Ownable(msg.sender) {
        i_userRegistry = UserRegistry(_userRegistryAddress);
        i_doctorRegistry = DoctorRegistry(_doctorRegistryAddress); // <-- Inicializar
        i_prescriptionToken = PrescriptionToken(_prescriptionTokenAddress);
    }

    // --- Automation Contract Management ---
    /**
     * @notice Sets the address of the automation contract that can call restricted functions.
     * @dev Can only be called by the contract owner.
     * @param _automationAddress The address of the automation contract.
     */
    function setAutomationContract(address _automationAddress) external onlyOwner {
        if (_automationAddress == address(0)) revert PrescriptionManager__InvalidAddress();
        s_automationContract = _automationAddress;
        emit AutomationContractSet(_automationAddress);
    }

    // --- Prescription Management ---
    /**
     * @notice Creates a new medical prescription and mints a corresponding NFT for the patient.
     * @dev Can only be called by a registered doctor. The patient must be an active user in the UserRegistry.
     *      The tokenURI should be a Base64 encoded JSON string generated off-chain.
     * @param _patientAddress The address of the patient receiving the prescription.
     * @param _medications The name of the medication.
     * @param _dosages The prescribed dosage.
     * @param _instructions The instructions for use.
     * @param _dueDate The timestamp when the prescription expires and becomes invalid.
     * @param _tokenURI The pre-formatted metadata URI for the NFT.
     */
    function createPrescription(
        address _patientAddress,
        string[] calldata _medications,
        string[] calldata _dosages,
        string[] calldata _instructions,
        uint256 _dueDate,
        string calldata _tokenURI
    ) external onlyDoctor {
        if (!_isUserRegistered(_patientAddress)) revert PrescriptionManager__PatientNotRegistered();

        uint256 prescriptionId = s_prescriptionCounter++;

        Medication[] memory medications = new Medication[](_medications.length);
        for (uint256 i = 0; i < _medications.length; i++) {
            medications[i] = Medication({name: _medications[i], dosage: _dosages[i], instructions: _instructions[i]});
        }

        s_prescriptions[prescriptionId] = Prescription({
            doctor: msg.sender,
            patient: _patientAddress,
            medications: medications,
            createdAt: block.timestamp,
            dueDate: _dueDate,
            status: PrescriptionStatus.Valid
        });

        s_idToIndexInActiveList[prescriptionId] = s_activePrescriptionIds.length;
        s_activePrescriptionIds.push(prescriptionId);
        s_doctorToCreatedPrescriptions[msg.sender].push(prescriptionId);

        i_prescriptionToken.safeMint(_patientAddress, prescriptionId, _tokenURI);

        emit PrescriptionCreated(prescriptionId, msg.sender, _patientAddress);
    }

    /**
     * @notice Allows a patient to share their prescription with another registered doctor.
     * @dev Can only be called by the owner of the prescription NFT (the patient). Reverts if already shared with the doctor.
     * @param _prescriptionId The ID of the prescription to share.
     * @param _doctorAddress The address of the doctor to grant access to.
     */
    function sharePrescription(uint256 _prescriptionId, address _doctorAddress) external {
        if (!_isTokenOwner(_prescriptionId, msg.sender)) {
            revert PrescriptionManager__OnlyPatientCanShare();
        }
        if (!_isDoctorRegistered(_doctorAddress)) revert PrescriptionManager__DoctorNotRegistered();
        if (s_prescriptionShares[_prescriptionId][_doctorAddress]) revert PrescriptionManager__AlreadyShared();

        s_prescriptionShares[_prescriptionId][_doctorAddress] = true;
        s_doctorToSharedPrescriptions[_doctorAddress].push(_prescriptionId);
        emit PrescriptionShared(_prescriptionId, _doctorAddress);
    }

    /**
     * @notice Invalidates an expired prescription and burns the associated NFT.
     * @dev Can only be called by the registered Automation contract. This function uses the swap-and-pop
     *      pattern to efficiently remove the ID from the active list.
     * @param _prescriptionId The ID of the prescription to invalidate.
     */
    function invalidatePrescription(uint256 _prescriptionId) external onlyAutomation {
        s_prescriptions[_prescriptionId].status = PrescriptionStatus.Expired;

        uint256 indexToRemove = s_idToIndexInActiveList[_prescriptionId];
        uint256 lastId = s_activePrescriptionIds[s_activePrescriptionIds.length - 1];

        s_activePrescriptionIds[indexToRemove] = lastId;
        s_idToIndexInActiveList[lastId] = indexToRemove;

        s_activePrescriptionIds.pop();
        delete s_idToIndexInActiveList[_prescriptionId];

        i_prescriptionToken.burn(_prescriptionId);
        emit PrescriptionInvalidated(_prescriptionId);
    }

    // --- View Functions ---
    /**
     * @notice Returns the list of all active prescription IDs.
     * @dev Intended to be called by the automation contract.
     * @return An array of active prescription IDs.
     */
    function getActivePrescriptionIds() external view onlyAutomation returns (uint256[] memory) {
        return s_activePrescriptionIds;
    }

    /**
     * @notice Retrieves all prescriptions created by or shared with the calling doctor.
     * @dev Can only be called by a registered doctor. It combines both lists (created and shared) into a single array.
     * @return prescriptions An array of on-chain Prescription structs.
     */
    function getDoctorPrescriptions() external view onlyDoctor returns (Prescription[] memory prescriptions) {
        uint256[] memory createdIds = s_doctorToCreatedPrescriptions[msg.sender];
        uint256[] memory sharedIds = s_doctorToSharedPrescriptions[msg.sender];

        uint256 totalCount = createdIds.length + sharedIds.length;
        prescriptions = new Prescription[](totalCount);

        uint256 currentIndex = 0;

        // Process created prescriptions
        for (uint256 i = 0; i < createdIds.length; i++) {
            uint256 pId = createdIds[i];
            prescriptions[currentIndex] = s_prescriptions[pId];
            currentIndex++;
        }

        // Process shared prescriptions
        for (uint256 i = 0; i < sharedIds.length; i++) {
            uint256 pId = sharedIds[i];
            prescriptions[currentIndex] = s_prescriptions[pId];
            currentIndex++;
        }

        return (prescriptions);
    }

    /**
     * @notice Retrieves the on-chain data for a single, specific prescription.
     * @dev Can only be called by a registered doctor. Access is restricted to the creating doctor or a doctor
     *      with whom the prescription was shared. It returns the on-chain struct, as it contains all necessary
     *      data for the doctor's application. The patient accesses full details via their NFT.
     * @param _prescriptionId The ID of the prescription to query.
     * @return The on-chain Prescription struct.
     */
    function getPrescriptionDetails(uint256 _prescriptionId) external view onlyDoctor returns (Prescription memory) {
        Prescription memory prescription = s_prescriptions[_prescriptionId];
        if (prescription.createdAt == 0) revert PrescriptionManager__PrescriptionNotFound();

        if (msg.sender != prescription.doctor && !s_prescriptionShares[_prescriptionId][msg.sender]) {
            revert PrescriptionManager__NotAuthorizedToView();
        }
        return prescription;
    }

    /**
     * @notice Internal function to check if a user is active in the UserRegistry.
     * @param _userAddress The address to check.
     * @return A boolean indicating if the user is active.
     */
    function _isUserRegistered(address _userAddress) internal view returns (bool) {
        return i_userRegistry.isUserActive(_userAddress);
    }

    /**
     * @notice Internal function to verify the owner of a prescription NFT.
     * @param _prescriptionId The ID of the token.
     * @param _userAddress The address to check.
     * @return A boolean indicating if the user is the owner.
     */
    function _isTokenOwner(uint256 _prescriptionId, address _userAddress) internal view returns (bool) {
        return i_prescriptionToken.ownerOf(_prescriptionId) == _userAddress;
    }

    /**
     * @notice Internal function to check if a doctor is registered.
     * @param _doctorAddress The address of the doctor to check.
     * @return A boolean indicating if the doctor is registered.
     */
    function _isDoctorRegistered(address _doctorAddress) internal view returns (bool) {
        return i_doctorRegistry.isDoctorRegistered(_doctorAddress);
    }
}
