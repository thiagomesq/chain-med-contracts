// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MedicalPrescriptions
 * @dev Contrato para gerenciar prescrições médicas na blockchain
 */
contract MedicalPrescriptions {
    // Custom Errors
    error MedicalPrescriptions__EmptyName();
    error MedicalPrescriptions__EmptyCRM();
    error MedicalPrescriptions__EmptyCPF();
    error MedicalPrescriptions__InvalidWalletAddress();
    error MedicalPrescriptions__DoctorAlreadyRegistered();
    error MedicalPrescriptions__PatientAlreadyRegistered();
    error MedicalPrescriptions__NotRegisteredDoctor();
    error MedicalPrescriptions__NotRegisteredPatient();
    error MedicalPrescriptions__NotRegisteredDoctorOrPatient();
    error MedicalPrescriptions__EmptyPatientId();
    error MedicalPrescriptions__EmptyMedication();
    error MedicalPrescriptions__PatientNotRegistered();
    error MedicalPrescriptions__InvalidPatientWalletAddress();
    error MedicalPrescriptions__EmptyPrescriptionId();
    error MedicalPrescriptions__PrescriptionNotFoundOrInvalid();
    error MedicalPrescriptions__DoctorNotRegistered();
    error MedicalPrescriptions__PrescriptionDoesNotBelongToPatient();

    // Estrutura para armazenar dados do médico
    struct Doctor {
        string name;
        string crm;
        string specialty;
        address walletAddress;
        bool isRegistered;
    }

    // Estrutura para armazenar dados do paciente
    struct Patient {
        string name;
        string cpf;
        string birthDate;
        address walletAddress;
        bool isRegistered;
    }

    // Estrutura para armazenar dados da prescrição
    struct Prescription {
        string id;
        string doctorId;
        string patientId;
        string medication;
        string dosage;
        string instructions;
        uint256 timestamp;
        bool isValid;
    }

    // Mapeamentos para armazenar dados
    mapping(string => Doctor) private doctors; // CRM -> Doctor
    mapping(address => string) private doctorAddresses; // Wallet -> CRM

    mapping(string => Patient) private patients; // CPF -> Patient
    mapping(address => string) private patientAddresses; // Wallet -> CPF

    mapping(string => Prescription) private prescriptions; // ID -> Prescription
    mapping(string => mapping(string => bool)) private patientPrescriptions; // PatientID -> PrescriptionID -> bool
    mapping(string => mapping(string => bool)) private doctorPrescriptions; // DoctorID -> PrescriptionID -> bool

    // Mapeamento para controle de acesso às prescrições
    mapping(string => mapping(string => bool)) private prescriptionAccess; // PrescriptionID -> DoctorID -> bool

    // Eventos
    event DoctorRegistered(string crm, address walletAddress);
    event PatientRegistered(string cpf, address walletAddress);
    event PrescriptionCreated(string prescriptionId, string doctorId, string patientId);
    event PrescriptionShared(string prescriptionId, string doctorId);

    // Modificadores
    modifier onlyDoctor() {
        if (bytes(doctorAddresses[msg.sender]).length == 0) {
            revert MedicalPrescriptions__NotRegisteredDoctor();
        }
        _;
    }

    modifier onlyPatient() {
        if (bytes(patientAddresses[msg.sender]).length == 0) {
            revert MedicalPrescriptions__NotRegisteredPatient();
        }
        _;
    }

    modifier onlyDoctorOrPatient() {
        if (bytes(doctorAddresses[msg.sender]).length == 0 && bytes(patientAddresses[msg.sender]).length == 0) {
            revert MedicalPrescriptions__NotRegisteredDoctorOrPatient();
        }
        _;
    }

    /**
     * @dev Registra um novo médico
     * @param name Nome do médico
     * @param crm CRM do médico
     * @param specialty Especialidade do médico
     * @param walletAddress Endereço da carteira do médico
     */
    function registerDoctor(string memory name, string memory crm, string memory specialty, address walletAddress)
        external
        returns (bool)
    {
        if (bytes(name).length == 0) revert MedicalPrescriptions__EmptyName();
        if (bytes(crm).length == 0) revert MedicalPrescriptions__EmptyCRM();
        if (walletAddress == address(0)) revert MedicalPrescriptions__InvalidWalletAddress();
        if (doctors[crm].isRegistered) revert MedicalPrescriptions__DoctorAlreadyRegistered();

        doctors[crm] =
            Doctor({name: name, crm: crm, specialty: specialty, walletAddress: walletAddress, isRegistered: true});

        doctorAddresses[walletAddress] = crm;

        emit DoctorRegistered(crm, walletAddress);

        return true;
    }

    /**
     * @dev Registra um novo paciente
     * @param name Nome do paciente
     * @param cpf CPF do paciente
     * @param birthDate Data de nascimento do paciente
     * @param walletAddress Endereço da carteira do paciente
     */
    function registerPatient(string memory name, string memory cpf, string memory birthDate, address walletAddress)
        external
        returns (bool)
    {
        if (bytes(name).length == 0) revert MedicalPrescriptions__EmptyName();
        if (bytes(cpf).length == 0) revert MedicalPrescriptions__EmptyCPF();
        if (walletAddress == address(0)) revert MedicalPrescriptions__InvalidWalletAddress();
        if (patients[cpf].isRegistered) revert MedicalPrescriptions__PatientAlreadyRegistered();

        patients[cpf] =
            Patient({name: name, cpf: cpf, birthDate: birthDate, walletAddress: walletAddress, isRegistered: true});

        patientAddresses[walletAddress] = cpf;

        emit PatientRegistered(cpf, walletAddress);

        return true;
    }

    /**
     * @dev Cria uma nova prescrição médica
     * @param patientId CPF do paciente
     * @param medication Nome do medicamento
     * @param dosage Dosagem do medicamento
     * @param instructions Instruções de uso
     * @param patientWalletAddress Endereço da carteira do paciente
     */
    function createPrescription(
        string memory patientId,
        string memory medication,
        string memory dosage,
        string memory instructions,
        address patientWalletAddress
    ) external onlyDoctor returns (string memory) {
        if (bytes(patientId).length == 0) revert MedicalPrescriptions__EmptyPatientId();
        if (bytes(medication).length == 0) revert MedicalPrescriptions__EmptyMedication();
        if (!patients[patientId].isRegistered) revert MedicalPrescriptions__PatientNotRegistered();
        if (patients[patientId].walletAddress != patientWalletAddress) revert MedicalPrescriptions__InvalidPatientWalletAddress();

        string memory doctorId = doctorAddresses[msg.sender];

        // Gerar ID único para a prescrição (em produção, usaria um método mais robusto)
        string memory prescriptionId = generatePrescriptionId(doctorId, patientId, block.timestamp);

        prescriptions[prescriptionId] = Prescription({
            id: prescriptionId,
            doctorId: doctorId,
            patientId: patientId,
            medication: medication,
            dosage: dosage,
            instructions: instructions,
            timestamp: block.timestamp,
            isValid: true
        });

        // Registrar a prescrição para o médico e paciente
        doctorPrescriptions[doctorId][prescriptionId] = true;
        patientPrescriptions[patientId][prescriptionId] = true;

        // Dar acesso ao médico que criou a prescrição
        prescriptionAccess[prescriptionId][doctorId] = true;

        emit PrescriptionCreated(prescriptionId, doctorId, patientId);

        return prescriptionId;
    }

    /**
     * @dev Compartilha uma prescrição com outro médico
     * @param prescriptionId ID da prescrição
     * @param doctorCrm CRM do médico com quem compartilhar
     */
    function sharePrescription(string memory prescriptionId, string memory doctorCrm)
        external
        onlyPatient
        returns (bool)
    {
        if (bytes(prescriptionId).length == 0) revert MedicalPrescriptions__EmptyPrescriptionId();
        if (bytes(doctorCrm).length == 0) revert MedicalPrescriptions__EmptyCRM();
        if (!prescriptions[prescriptionId].isValid) revert MedicalPrescriptions__PrescriptionNotFoundOrInvalid();
        if (!doctors[doctorCrm].isRegistered) revert MedicalPrescriptions__DoctorNotRegistered();

        string memory patientId = patientAddresses[msg.sender];

        // Verificar se a prescrição pertence ao paciente
        if (!patientPrescriptions[patientId][prescriptionId]) revert MedicalPrescriptions__PrescriptionDoesNotBelongToPatient();

        // Dar acesso ao médico
        prescriptionAccess[prescriptionId][doctorCrm] = true;

        emit PrescriptionShared(prescriptionId, doctorCrm);

        return true;
    }

    /**
     * @dev Verifica se uma prescrição é válida
     * @param prescriptionId ID da prescrição
     */
    function verifyPrescription(string memory prescriptionId) external view onlyDoctorOrPatient returns (bool) {
        if (bytes(prescriptionId).length == 0) revert MedicalPrescriptions__EmptyPrescriptionId();

        // Verificar se a prescrição existe e é válida
        if (!prescriptions[prescriptionId].isValid) {
            return false;
        }

        // Se o chamador for um médico, verificar se tem acesso
        if (bytes(doctorAddresses[msg.sender]).length > 0) {
            string memory doctorId = doctorAddresses[msg.sender];
            return prescriptionAccess[prescriptionId][doctorId];
        }

        // Se o chamador for um paciente, verificar se a prescrição pertence a ele
        if (bytes(patientAddresses[msg.sender]).length > 0) {
            string memory patientId = patientAddresses[msg.sender];
            return patientPrescriptions[patientId][prescriptionId];
        }

        return false;
    }

    /**
     * @dev Gera um ID único para a prescrição
     * @param doctorId ID do médico
     * @param patientId ID do paciente
     * @param timestamp Timestamp da criação
     */
    function generatePrescriptionId(string memory doctorId, string memory patientId, uint256 timestamp)
        private
        pure
        returns (string memory)
    {
        // Em uma implementação real, usaria um método mais robusto para gerar IDs únicos
        // Esta é uma simplificação para o exemplo
        return string(abi.encode("RX", doctorId, patientId, uint2str(timestamp)));
    }

    /**
     * @dev Converte um uint para string
     * @param _i Número a ser convertido
     */
    function uint2str(uint256 _i) private pure returns (string memory) {
        uint256 div = 10; 
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len = 0;
        while (j != 0) {
            len++;
            j /= div;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 100));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= div;
        }
        return string(bstr);
    }
}
