// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IMetadataHandler.sol";

import "forge-std/console.sol";

/**
 * @title FNFTHandler
 * @author 0xTraub
 */
contract FNFTHandler is IFNFTHandler, ERC1155, AccessControl  {
    using ERC165Checker for address;
    using SafeCast for uint256;
    using ECDSA for bytes32;

    //Permit Signature Stuff
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 public constant SETAPPROVALFORALL_TYPEHASH = keccak256(
        "transferFromWithPermit(address owner,address operator, bool approved, uint id, uint amount, uint256 deadline, uint nonce, bytes data)"
    );

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address signer => uint256 nonce) public nonces;

    struct ids {
        address controller;
        uint96 supply;
    }

    mapping(uint256 => ids) private supply;

    // Modified to start at 1 to make use of TokenVaultV2 far simpler
    uint256 public fnftsCreated = 1;

    /**
     * @dev Primary constructor to create an instance of NegativeEntropy
     * Grants ADMIN and MINTER_ROLE to whoever creates the contract
     */
    constructor(string memory _uri, address govController) ERC1155(_uri) {
        DOMAIN_SEPARATOR =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Revest_FNFTHandler")), block.chainid, address(this)));

        //Grant Minting Power to the Revest Controller
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);

        //Grant Ability to grant minting power to the Governance Controller
        _grantRole(DEFAULT_ADMIN_ROLE, govController);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165, AccessControl) returns (bool) {
        return interfaceId == type(IFNFTHandler).interfaceId //IFNFTHandler
            || interfaceId == type(IERC1155Supply).interfaceId //IERC1155Supply
            || interfaceId == type(AccessControl).interfaceId //IMetadataHandler
            || super.supportsInterface(interfaceId); //ERC1155
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external override onlyRole(CONTROLLER_ROLE) {
        //If its a new ID then create a new struct, otherwise only increase supply
        if (supply[id].supply == 0) {
            supply[id] = ids({controller: msg.sender, supply: amount.toUint96()});
        } else {
            supply[id].supply += amount.toUint96();
        }

        fnftsCreated += 1;
        _mint(account, id, amount, data);

        //Trigger Opensea Caching
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function burn(address account, uint256 id, uint256 amount) external override onlyRole(CONTROLLER_ROLE) {
        ids storage fnft = supply[id];
        require(msg.sender == fnft.controller, "E017");

        fnft.supply -= amount.toUint96();
        
        _burn(account, id, amount);

        //Trigger Opensea Caching
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function totalSupply(uint256 fnftId) public view override returns (uint256) {
        return supply[fnftId].supply;
    }

    function exists(uint256 id) external view returns (bool) {
        //According to the spec this should return if a token id "exists, previously existed, or may exist"
        //It's unclear whether or not this should return true for a token that has been burned, so i went with "currently exists"
        return supply[id].supply != 0;
    }

    function getNextId() public view override returns (uint256) {
        return fnftsCreated;
    }

    function transferFromWithPermit(permitApprovalInfo memory info, bytes memory signature) external {
        uint256 nonce = nonces[info.owner]++;

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        SETAPPROVALFORALL_TYPEHASH,
                        info.owner,
                        info.operator,
                        true,
                        info.id,
                        info.amount,
                        info.deadline,
                        nonce,
                        info.data
                    )
                )
            )
        );

        (address signer,,) = digest.tryRecover(signature);

        require(signer != address(0) && signer == info.owner, "E018");
        require(block.timestamp < info.deadline, "ERC1155: signature expired");

        _setApprovalForAll(info.owner, info.operator, true);
        _safeTransferFrom(info.owner, info.operator, info.id, info.amount, info.data);
    }

    // OVERIDDEN ERC-1155 METHODS
    function uri(uint256 fnftId) public view override(ERC1155, IFNFTHandler) returns (string memory) {
        bytes32 salt = keccak256(abi.encode(fnftId, address(this), 0));
        return IRevest(supply[fnftId].controller).getTokenURI(salt);
    }
    
    function renderTokenURI(uint256 tokenId)
        external
        view
        returns (string memory baseRenderURI, string[] memory parameters)
    {
        address controller = supply[tokenId].controller;
        bytes32 salt = keccak256(abi.encode(tokenId, address(this), 0));
        return IRevest(controller).renderTokenURI(salt, controller);
    }
}
