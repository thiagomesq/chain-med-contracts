// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UserRegistry} from "./UserRegistry.sol";

/**
 * @title MedicalAssetToken
 * @author ChainMed Team
 * @notice Represents a "Declaração Pessoal de Saúde" (DPS) as a non-transferable, non-burnable ERC721 token (Soulbound Token).
 * @dev This token is minted by the DPSManager contract upon DPS registration. Transfers and burning are disabled
 *      after minting to ensure the token remains a permanent, unchangeable record linked to its original owner.
 */
contract MedicalAssetToken is ERC721URIStorage, Ownable {
    // Custom Errors
    error MedicalAssetToken__UnauthorizedUser();
    error MedicalAssetToken__TransferNotAllowed();
    error MedicalAssetToken__TokenIdDoesNotExist();
    error MedicalAssetToken__TokenIdNotFound();
    error MedicalAssetToken__BurningNotAllowed();

    // State Variables
    UserRegistry public immutable i_userRegistry;
    address public immutable i_dpsManager;
    uint256 private _nextTokenId;

    mapping(uint256 => bytes32) public assetToDataRecordHash;
    mapping(bytes32 => uint256) public hashToTokenId;

    // Events
    event AssetLinkedToData(uint256 indexed tokenId, bytes32 indexed hashDPS);

    /**
     * @notice Modifier to ensure a function is called only by the DPSManager contract or the contract owner.
     */
    modifier onlyDPSManagerOrOwner() {
        if (msg.sender != i_dpsManager && msg.sender != owner()) {
            revert MedicalAssetToken__UnauthorizedUser();
        }
        _;
    }

    /**
     * @dev Initializes the contract with the UserRegistry and DPSManager addresses.
     * @param _userRegistryAddress Address of the deployed UserRegistry contract.
     * @param _dpsManagerAddress Address of the deployed DPSManager contract.
     */
    constructor(address _userRegistryAddress, address _dpsManagerAddress)
        ERC721("ChainMed Medical Asset", "CMMA")
        Ownable(msg.sender)
    {
        i_userRegistry = UserRegistry(_userRegistryAddress);
        i_dpsManager = _dpsManagerAddress;
    }

    /**
     * @notice Mints a new asset token.
     * @dev This function is designed to be called exclusively by the DPSManager contract upon successful
     *      DPS registration. It creates the token and links it to the DPS hash.
     * @param ownerAddress The address of the new token owner.
     * @param hashDPS The keccak256 hash of the DPS document, used for linking.
     * @param tokenURI The Base64 encoded metadata for the token.
     */
    function safeMint(address ownerAddress, bytes32 hashDPS, string calldata tokenURI) external onlyDPSManagerOrOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(ownerAddress, tokenId);
        assetToDataRecordHash[tokenId] = hashDPS;
        hashToTokenId[hashDPS] = tokenId;
        _setTokenURI(tokenId, tokenURI);
        emit AssetLinkedToData(tokenId, hashDPS);
    }

    /**
     * @notice Overrides the internal _update function to make the token non-transferable and non-burnable (Soulbound).
     * @dev This is the standard hook for customizing transfers in OpenZeppelin v5.x.
     *      - Minting is allowed via the safeMint function.
     *      - Burning (transfer to address(0)) is explicitly disabled.
     *      - Standard transfers between two non-zero addresses are disabled.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Disallow burning
        if (to == address(0)) {
            revert MedicalAssetToken__BurningNotAllowed();
        }

        // A standard transfer occurs when 'from' and 'to' are not the zero address.
        if (from != address(0)) {
            revert MedicalAssetToken__TransferNotAllowed();
        }

        // For minting (from == 0), check if the receiver is an active user.
        if (!i_userRegistry.isUserActive(to)) {
            revert MedicalAssetToken__UnauthorizedUser();
        }

        // After checks, call the parent's _update function and return its result.
        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Retrieves the token ID associated with a given DPS hash.
     * @dev Uses a reverse mapping for a gas-efficient O(1) lookup.
     * @param hashDPS The keccak256 hash of the DPS to find the associated token ID.
     * @return The token ID associated with the given DPS hash.
     */
    function getTokenIdByHash(bytes32 hashDPS) external view onlyDPSManagerOrOwner returns (uint256) {
        if (_nextTokenId == 0) {
            revert MedicalAssetToken__TokenIdDoesNotExist();
        }
        uint256 tokenId = hashToTokenId[hashDPS];
        if (
            tokenId == 0
                && keccak256(abi.encodePacked(assetToDataRecordHash[0])) != keccak256(abi.encodePacked(hashDPS))
        ) {
            revert MedicalAssetToken__TokenIdNotFound();
        }
        return tokenId;
    }

    /**
     * @dev Returns the base URI for the token metadata.
     *      This is used to construct the full URI for each token.
     */
    function _baseURI() internal pure override returns (string memory) {
        return "data:application/json;base64,";
    }
}
