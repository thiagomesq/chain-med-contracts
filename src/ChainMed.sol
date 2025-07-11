// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;
/**
 * @title ChainMed
 * @author Thiago Borges, Thiago Mesquita
 * @notice Sistema de gerenciamento de prescrições médicas
 * @dev Contrato para gerenciar prescrições médicas na blockchain
 */

contract ChainMed {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ChainMed__OnlyDoctorsAuthorized();
    error ChainMed__DoctorAlreadyRegistered();
    error ChainMed__PatientAlreadyRegistered();
    error ChainMed__CRMAlreadyRegistered();
    error ChainMed__CPFAlreadyRegistered();
    error ChainMed__DoctorNotRegistered();
    error ChainMed__PatientNotRegistered();
    error ChainMed__PrescriptionNotFound();
    error ChainMed__ViewPrescriptionNotAuthorized();
    error ChainMed__OnlyThePatientOwnerCanShare(); 

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct Doctor {
        string name;
        string crm;
        string specialty;
        bool isRegistered;
    }

    struct Patient {
        string name;
        string cpf;
        bool isRegistered;
    }

    struct Prescription {
        uint256 id;
        address doctor;
        address patient;
        string medication;
        string dosage;
        string instructions;
        uint256 timestamp;
        bool isValid;
    }

    struct SharedPrescription {
        uint256 prescriptionId;
        address sharedWith;
        uint256 timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    mapping(address => Doctor) private s_doctors;
    mapping(address => Patient) private s_patients;
    mapping(string => bool) private s_usedCRMs;
    mapping(string => bool) private s_usedCPFs;
    mapping(uint256 => Prescription) private s_prescriptions;
    mapping(uint256 => SharedPrescription[]) private s_prescriptionShares;
    uint256 private s_prescriptionCounter = 0;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event DoctorRegistered(address indexed doctorAddress, string name, string crm);
    event PatientRegistered(address indexed patientAddress, string name, string cpf);
    event PrescriptionCreated(uint256 indexed prescriptionId, address indexed doctor, address indexed patient);
    event PrescriptionShared(uint256 indexed prescriptionId, address indexed sharedWith);

    /*//////////////////////////////////////////////////////////////
                          FUNCTIONS - EXTERNAL
    //////////////////////////////////////////////////////////////*/
    // Register a new doctor
    function registerDoctor(string memory _name, string memory _crm, string memory _specialty) external {
        if (s_doctors[msg.sender].isRegistered) {
            revert ChainMed__DoctorAlreadyRegistered();
        }
        if (s_usedCRMs[_crm]) {
            revert ChainMed__CRMAlreadyRegistered();
        }

        s_doctors[msg.sender] = Doctor(_name, _crm, _specialty, true);
        s_usedCRMs[_crm] = true;

        emit DoctorRegistered(msg.sender, _name, _crm);
    }

    // Register a new patient
    function registerPatient(string memory _name, string memory _cpf) external {
        if (s_patients[msg.sender].isRegistered) {
            revert ChainMed__PatientAlreadyRegistered();
        }
        if (s_usedCPFs[_cpf]) {
            revert ChainMed__CPFAlreadyRegistered();
        }

        bool isRegistered = true;
        s_patients[msg.sender] = Patient(_name, _cpf, isRegistered);
        s_usedCPFs[_cpf] = true;

        emit PatientRegistered(msg.sender, _name, _cpf);
    }

    // Create a new prescription
    function createPrescription(
        address _patientAddress,
        string memory _medication,
        string memory _dosage,
        string memory _instructions
    ) external {
        if (!s_doctors[msg.sender].isRegistered) {
            revert ChainMed__OnlyDoctorsAuthorized();
        }
        if (!s_patients[_patientAddress].isRegistered) {
            revert ChainMed__PatientNotRegistered();
        }

        uint256 prescriptionId = s_prescriptionCounter++;
        s_prescriptions[prescriptionId] = Prescription(
            prescriptionId, msg.sender, _patientAddress, _medication, _dosage, _instructions, block.timestamp, true
        );

        emit PrescriptionCreated(prescriptionId, msg.sender, _patientAddress);
    }

    // Share a prescription with another doctor
    function sharePrescription(uint256 _prescriptionId, address _doctorAddress) external {
        Prescription memory prescription = s_prescriptions[_prescriptionId];
        if (!prescription.isValid) {
            revert ChainMed__PrescriptionNotFound();
        }
        if (msg.sender != prescription.patient) {
            revert ChainMed__OnlyThePatientOwnerCanShare();
        }
        if (!s_doctors[_doctorAddress].isRegistered) {
            revert ChainMed__DoctorNotRegistered();
        }

        s_prescriptionShares[_prescriptionId].push(SharedPrescription(_prescriptionId, _doctorAddress, block.timestamp));

        emit PrescriptionShared(_prescriptionId, _doctorAddress);
    }

    /*//////////////////////////////////////////////////////////////
                         FUNCTIONS - VIEW/PURE
    //////////////////////////////////////////////////////////////*/
    // Get the prescriptions of the sender
    function getPrescriptions() external view returns (Prescription[] memory) {
        uint256 totalPrescriptions = s_prescriptionCounter;
        Prescription[] memory prescriptions = new Prescription[](totalPrescriptions);
        for (uint256 i = 0; i < totalPrescriptions; i++) {
            Prescription memory prescription = s_prescriptions[i];
            if ((msg.sender == prescription.doctor || 
                msg.sender == prescription.patient || 
                isSharedWith(i, msg.sender)) && prescription.isValid
            ) {
                prescriptions[i] = prescription;
            }
        }
        return prescriptions;
    }
    // Get prescription details
    function getPrescription(uint256 _prescriptionId) external view returns (Prescription memory) {
        Prescription memory prescription = s_prescriptions[_prescriptionId];
        if (!prescription.isValid) {
            revert ChainMed__PrescriptionNotFound();
        }
        if (
            msg.sender != prescription.doctor && msg.sender != prescription.patient
                && !isSharedWith(_prescriptionId, msg.sender)
        ) {
            revert ChainMed__ViewPrescriptionNotAuthorized();
        }

        return prescription;
    }

    // Get doctor details
    function getDoctorDetails(address _doctorAddress) external view returns (Doctor memory) {
        if (!isDoctor(_doctorAddress)) {
            revert ChainMed__DoctorNotRegistered();
        }
        return s_doctors[_doctorAddress];
    }

    // Get patient details
    function getPatientDetails(address _patientAddress) external view returns (Patient memory) {
        if (!isPatient(_patientAddress)) {
            revert ChainMed__PatientNotRegistered();
        }
        return s_patients[_patientAddress];
    }

    // Check if an address is registered as a doctor
    function isDoctor(address _address) public view returns (bool) {
        return s_doctors[_address].isRegistered;
    }

    // Check if an address is registered as a patient
    function isPatient(address _address) public view returns (bool) {
        return s_patients[_address].isRegistered;
    }

    // Check if prescription is shared with an address
    function isSharedWith(uint256 _prescriptionId, address _address) internal view returns (bool) {
        SharedPrescription[] memory shares = s_prescriptionShares[_prescriptionId];
        for (uint256 i = 0; i < shares.length; i++) {
            if (shares[i].sharedWith == _address) {
                return true;
            }
        }
        return false;
    }
}
