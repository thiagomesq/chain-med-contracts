// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PrescriptionToken
 * @author ChainMed Team
 * @notice Represents a medical prescription as a non-transferable NFT (RWA).
 * @dev This token is soulbound to the patient (non-transferable), but can be burned.
 *      Minting and Burning are controlled exclusively by the PrescriptionManager contract.
 */
contract PrescriptionToken is ERC721URIStorage, Ownable {
    // Custom Errors
    error PrescriptionToken__InvalidAddress();
    error PrescriptionToken__TransferNotAllowed();
    error PrescriptionToken__OnlyManagerAllowed();

    address public s_managerAddress;

    // Events
    event ManagerSet(address indexed managerAddress);

    // Modifiers
    modifier onlyManager() {
        if (msg.sender != s_managerAddress) revert PrescriptionToken__OnlyManagerAllowed();
        _;
    }

    constructor() ERC721("ChainMed Prescription", "CMP") Ownable(msg.sender) {}

    /**
     * @notice Sets the address of the manager contract that is allowed to mint tokens.
     * @param _managerAddress The address of the PrescriptionManager contract.
     */
    function setManager(address _managerAddress) external onlyOwner {
        if (_managerAddress == address(0)) revert PrescriptionToken__InvalidAddress();
        s_managerAddress = _managerAddress;
        emit ManagerSet(_managerAddress);
    }

    /**
     * @notice Mints a new prescription token.
     * @dev Can only be called by the registered manager contract.
     * @param _patient The address of the patient who will own the token.
     * @param _tokenId The unique ID for the new token.
     * @param _tokenURI The metadata (prescription details) for the token.
     */
    function safeMint(address _patient, uint256 _tokenId, string calldata _tokenURI) external onlyManager {
        _safeMint(_patient, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
    }

    /**
     * @notice Burns an existing prescription token.
     * @dev Can only be called by the registered manager contract, typically after a prescription is invalidated.
     * @param _tokenId The unique ID of the token to burn.
     */
    function burn(uint256 _tokenId) external onlyManager {
        _burn(_tokenId);
    }

    /**
     * @notice Overrides the internal _update function to enforce transfer rules.
     * @dev Allows minting (from address(0)) and burning (to address(0)), but disallows standard transfers.
     *      The `onlyManager` modifier on `safeMint` and `burn` functions provides the primary access control.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            revert PrescriptionToken__TransferNotAllowed();
        }

        return super._update(to, tokenId, auth);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }
}
