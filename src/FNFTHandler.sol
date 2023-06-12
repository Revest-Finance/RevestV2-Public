// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IMetadataHandler.sol";

/**
 * @title FNFTHandler
 * @author 0xTraub
 */
contract FNFTHandler is ERC1155, Ownable, IFNFTHandler {
    using ERC165Checker for address;
    using ECDSA for bytes32;

    //Permit Signature Stuff
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    bytes32 public constant SETAPPROVALFORALL_TYPEHASH = keccak256(
        "transferFromWithPermit(address owner,address operator, bool approved, uint id, uint amount, uint256 deadline, uint nonce, bytes data)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address signer => uint256 nonce) public nonces;

    mapping(uint256 => uint256) private supply;

    // Modified to start at 1 to make use of TokenVaultV2 far simpler
    uint256 public fnftsCreated = 1;

    /**
     * @dev Primary constructor to create an instance of NegativeEntropy
     * Grants ADMIN and MINTER_ROLE to whoever creates the contract
     */
    constructor(address _revest, string memory _uri) ERC1155(_uri) Ownable() {
        DOMAIN_SEPARATOR =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("Revest_FNFTHandler")), block.chainid, address(this)));

        _transferOwnership(_revest);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IFNFTHandler).interfaceId //IFNFTHandler
            || interfaceId == type(IERC1155Supply).interfaceId //IERC1155Supply
            || super.supportsInterface(interfaceId); //ERC1155
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external override onlyOwner {
        supply[id] += amount;
        fnftsCreated += 1;
        _mint(account, id, amount, data);
    }

    function burn(address account, uint256 id, uint256 amount) external override onlyOwner {
        supply[id] -= amount;
        _burn(account, id, amount);
    }

    function totalSupply(uint256 fnftId) public view override returns (uint256) {
        return supply[fnftId];
    }

    function exists(uint256 id) external view returns (bool) {
        //According to the spec this should return if a token id "exists, previously existed, or may exist"
        //It's unclear whether or not this should return true for a token that has been burned, so i went with "currently exists"
        return supply[id] != 0;
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

        (address signer,) = digest.tryRecover(signature);

        require(signer != address(0) && signer == info.owner, "E018");
        require(block.timestamp < info.deadline, "ERC1155: signature expired");

        _setApprovalForAll(info.owner, info.operator, true);
        _safeTransferFrom(info.owner, info.operator, info.id, info.amount, info.data);
    }

    // OVERIDDEN ERC-1155 METHODS

    function _beforeTokenTransfer(
        address,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal view override {
        // Loop because all batch transfers must be checked
        // Will only execute once on singular transfer
        if (from != address(0)) {
            IRevest revest = IRevest(owner());

            for (uint256 x = 0; x < ids.length;) {
                bytes32 salt = keccak256(abi.encode(ids[x], address(this), 0));

                require(amounts[x] != 0, "E020");
                IRevest.FNFTConfig memory config = revest.getFNFT(salt);

                //OZ-1155 prevents transfers to the zero-address so we use dead address instead
                require(!config.nontransferrable || to == address(0xdead), "E022");

                unchecked {
                    ++x;
                }
            }
        }
    }

    function uri(uint256 fnftId) public view override(ERC1155, IFNFTHandler) returns (string memory) {
        bytes32 salt = keccak256(abi.encode(fnftId, address(this), 0));
        return IRevest(owner()).getTokenURI(salt);
    }

    function renderTokenURI(uint256 tokenId, address _owner)
        external
        view
        returns (string memory baseRenderURI, string[] memory parameters)
    {
        bytes32 salt = keccak256(abi.encode(tokenId, address(this), 0));
        return IRevest(owner()).renderTokenURI(salt, _owner);
    }
}
