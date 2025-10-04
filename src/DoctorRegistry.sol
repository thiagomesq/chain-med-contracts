// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DoctorRegistry
 * @author ChainMed Team
 * @notice Manages the registration and identity of doctors in the system.
 * @dev Serves as the single source of truth for doctor verification.
 */
contract DoctorRegistry is Ownable {
    // Errors
    error DoctorRegistry__DoctorAlreadyRegistered();
    error DoctorRegistry__CRMAlreadyRegistered();
    error DoctorRegistry__DoctorNotRegistered();

    // Structs
    struct Doctor {
        string name;
        string crm;
        string specialty;
        bool isRegistered;
    }

    // State Variables
    mapping(address => Doctor) private s_doctors;
    mapping(string => bool) private s_usedCRMs;
    address[] private s_doctorAddresses;

    // Events
    event DoctorRegistered(address indexed doctorAddress, string name, string crm);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Registers the calling address as a doctor.
     * @param _name The name of the doctor.
     * @param _crm The CRM (medical registration number) of the doctor.
     * @param _specialty The specialty of the doctor.
     * @dev Reverts if the doctor is already registered or if the CRM is already in
     */
    function registerDoctor(string calldata _name, string calldata _crm, string calldata _specialty) external {
        if (s_doctors[msg.sender].isRegistered) revert DoctorRegistry__DoctorAlreadyRegistered();
        if (s_usedCRMs[_crm]) revert DoctorRegistry__CRMAlreadyRegistered();

        s_doctors[msg.sender] = Doctor(_name, _crm, _specialty, true);
        s_usedCRMs[_crm] = true;
        s_doctorAddresses.push(msg.sender);
        emit DoctorRegistered(msg.sender, _name, _crm);
    }

    // --- View Functions ---
    /**
     * @notice Checks if a given address is a registered doctor.
     * @return A boolean indicating registration status.
     */
    function isDoctorRegistered(address _doctorAddress) external view returns (bool) {
        return s_doctors[_doctorAddress].isRegistered;
    }

    /**
     * @notice Retrieves the details of a registered doctor.
     * @return The Doctor struct.
     */
    function getDoctorDetails(address _doctorAddress) external view returns (Doctor memory) {
        if (!s_doctors[_doctorAddress].isRegistered) revert DoctorRegistry__DoctorNotRegistered();
        return s_doctors[_doctorAddress];
    }

    /**
     * @notice Retrieves a list of all registered doctors.
     * @dev This function is public and has no access restrictions.
     * @return An array of Doctor structs containing the details of all doctors.
     */
    function getAllDoctors() external view returns (Doctor[] memory) {
        uint256 doctorCount = s_doctorAddresses.length;
        if (doctorCount == 0) return new Doctor[](0);
        Doctor[] memory allDoctors = new Doctor[](doctorCount);
        for (uint256 i = 0; i < doctorCount; i++) {
            allDoctors[i] = s_doctors[s_doctorAddresses[i]];
        }
        return allDoctors;
    }

    /**
     * @notice Returns the total number of registered doctors.
     * @return The count of registered doctors.
     */
    function getDoctorCount() external view returns (uint256) {
        return s_doctorAddresses.length;
    }
}
