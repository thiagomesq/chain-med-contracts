
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract TuringRX {
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
    
    mapping(address => Doctor) public doctors;
    mapping(address => Patient) public patients;
    mapping(string => bool) public usedCRMs;
    mapping(string => bool) public usedCPFs;
    mapping(uint256 => Prescription) public prescriptions;
    mapping(uint256 => SharedPrescription[]) public prescriptionShares;
    
    uint256 private prescriptionCounter = 0;
    
    event DoctorRegistered(address indexed doctorAddress, string name, string crm);
    event PatientRegistered(address indexed patientAddress, string name, string cpf);
    event PrescriptionCreated(uint256 indexed prescriptionId, address indexed doctor, address indexed patient);
    event PrescriptionShared(uint256 indexed prescriptionId, address indexed sharedWith);
    
    modifier onlyDoctor() {
        require(doctors[msg.sender].isRegistered, "Only registered doctors can perform this action");
        _;
    }
    
    modifier onlyPatient() {
        require(patients[msg.sender].isRegistered, "Only registered patients can perform this action");
        _;
    }
    
    // Register a new doctor
    function registerDoctor(string memory _name, string memory _crm, string memory _specialty) external {
        require(!doctors[msg.sender].isRegistered, "Doctor already registered");
        require(!usedCRMs[_crm], "CRM already registered");
        
        doctors[msg.sender] = Doctor(_name, _crm, _specialty, true);
        usedCRMs[_crm] = true;
        
        emit DoctorRegistered(msg.sender, _name, _crm);
    }
    
    // Register a new patient
    function registerPatient(string memory _name, string memory _cpf) external {
        require(!patients[msg.sender].isRegistered, "Patient already registered");
        require(!usedCPFs[_cpf], "CPF already registered");
        
        patients[msg.sender] = Patient(_name, _cpf, true);
        usedCPFs[_cpf] = true;
        
        emit PatientRegistered(msg.sender, _name, _cpf);
    }
    
    // Create a new prescription
    function createPrescription(
        address _patientAddress,
        string memory _medication,
        string memory _dosage,
        string memory _instructions
    ) external onlyDoctor {
        require(patients[_patientAddress].isRegistered, "Patient not registered");
        
        uint256 prescriptionId = prescriptionCounter++;
        prescriptions[prescriptionId] = Prescription(
            prescriptionId,
            msg.sender,
            _patientAddress,
            _medication,
            _dosage,
            _instructions,
            block.timestamp,
            true
        );
        
        emit PrescriptionCreated(prescriptionId, msg.sender, _patientAddress);
    }
    
    // Share a prescription with another doctor
    function sharePrescription(uint256 _prescriptionId, address _doctorAddress) external {
        Prescription memory prescription = prescriptions[_prescriptionId];
        require(prescription.isValid, "Prescription does not exist");
        require(prescription.patient == msg.sender, "Only the patient can share their prescriptions");
        require(doctors[_doctorAddress].isRegistered, "Can only share with registered doctors");
        
        prescriptionShares[_prescriptionId].push(SharedPrescription(
            _prescriptionId,
            _doctorAddress,
            block.timestamp
        ));
        
        emit PrescriptionShared(_prescriptionId, _doctorAddress);
    }
    
    // Get prescription details
    function getPrescription(uint256 _prescriptionId) external view returns (Prescription memory) {
        Prescription memory prescription = prescriptions[_prescriptionId];
        require(prescription.isValid, "Prescription does not exist");
        require(
            msg.sender == prescription.doctor ||
            msg.sender == prescription.patient ||
            isSharedWith(_prescriptionId, msg.sender),
            "Not authorized to view this prescription"
        );
        
        return prescription;
    }
    
    // Check if prescription is shared with an address
    function isSharedWith(uint256 _prescriptionId, address _address) internal view returns (bool) {
        SharedPrescription[] memory shares = prescriptionShares[_prescriptionId];
        for (uint i = 0; i < shares.length; i++) {
            if (shares[i].sharedWith == _address) {
                return true;
            }
        }
        return false;
    }
    
    // Get doctor details
    function getDoctorDetails(address _doctorAddress) external view returns (Doctor memory) {
        require(doctors[_doctorAddress].isRegistered, "Doctor not registered");
        return doctors[_doctorAddress];
    }
    
    // Get patient details
    function getPatientDetails(address _patientAddress) external view returns (Patient memory) {
        require(patients[_patientAddress].isRegistered, "Patient not registered");
        return patients[_patientAddress];
    }
    
    // Check if an address is registered as a doctor
    function isDoctor(address _address) external view returns (bool) {
        return doctors[_address].isRegistered;
    }
    
    // Check if an address is registered as a patient
    function isPatient(address _address) external view returns (bool) {
        return patients[_address].isRegistered;
    }
}