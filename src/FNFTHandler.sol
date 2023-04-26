// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/IAddressRegistry.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IAddressLock.sol";
import "./utils/RevestAccessControl.sol";

import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IMetadataHandler.sol";
import "./interfaces/IOutputReceiver.sol";

contract FNFTHandler is ERC1155, AccessControl, RevestAccessControl, IFNFTHandler {

    using ERC165Checker for address;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes4 public constant OUTPUT_RECEIVER_INTERFACE_ID = type(IOutputReceiver).interfaceId;

    mapping(uint => uint) public supply;

    // Modified to start at 1 to make use of TokenVaultV2 far simpler
    uint public fnftsCreated = 1;

    /**
     * @dev Primary constructor to create an instance of NegativeEntropy
     * Grants ADMIN and MINTER_ROLE to whoever creates the contract
     */
    constructor(address provider) ERC1155("") RevestAccessControl(provider) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override (AccessControl, ERC1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function mint(address account, uint id, uint amount, bytes memory data) external override onlyRevestController {
        supply[id] += amount;
        fnftsCreated += 1;
        _mint(account, id, amount, data);
    }

    function mintBatchRec(address[] calldata recipients, uint[] calldata quantities, uint id, uint newSupply, bytes memory data) external override onlyRevestController {
        supply[id] += newSupply;
        fnftsCreated += 1;
        for(uint i = 0; i < quantities.length; i++) {
            _mint(recipients[i], id, quantities[i], data);
        }
    }

    function mintBatch(address to, uint[] memory ids, uint[] memory amounts, bytes memory data) external override onlyRevestController {}

    function setURI(string memory newuri) external override onlyRevestController {
        _setURI(newuri);
    }

    function burn(address account, uint id, uint amount) external override onlyRevestController {
        supply[id] -= amount;
        _burn(account, id, amount);
    }

    // NB: In its current state, this function is not used anywhere; it is also not safe
    function burnBatch(address account, uint[] memory ids, uint[] memory amounts) external override onlyRevestController {
        _burnBatch(account, ids, amounts);
    }

    function getBalance(address account, uint id) external view override returns (uint) {
        return balanceOf(account, id);
    }

    function getSupply(uint fnftId) public view override returns (uint) {
        return supply[fnftId];
    }

    function getNextId() public view override returns (uint) {
        return fnftsCreated;
    }


    // OVERIDDEN ERC-1155 METHODS

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint[] memory ids,
        uint[] memory amounts,
        bytes memory data
    ) internal override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        // Loop because all batch transfers must be checked
        // Will only execute once on singular transfer
        if (from != address(0) ) {
            address revest = addressesProvider.getRevest();

            //salt = keccak256(abi.encode(fnftId, handler, fnftNum));
            //handler is this and fnftNum is always zero for an 1155
            bytes32 salt = keccak256(abi.encode(ids[0], address(this), 0));

            IRevest.FNFTConfig memory config = IRevest(revest).getFNFT(salt);
            if(config.pipeToContract != address(0) && config.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
                IOutputReceiver(config.pipeToContract).onTransferFNFT(ids[0], operator, from, to, amounts[0], data);
            }
            bool canTransfer = !config.nontransferrable;
            // Only check if not from minter
            // And not being burned
            if(ids.length > 1) {
                uint i = 1;
                while (canTransfer && i < ids.length) {
                    require(amounts[i] > 0, "Trying to transfer zero tokens");
                    config = IRevest(revest).getFNFT(salt);
                    if(config.pipeToContract != address(0) && config.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
                        IOutputReceiver(config.pipeToContract).onTransferFNFT(ids[i], operator, from, to, amounts[i], data);
                    }
                    canTransfer = !config.nontransferrable;
                    i += 1;

                }
            }
            canTransfer = to == address(0) ? true : canTransfer;
            require(canTransfer, "E046");
        }
    }


    function uri(uint fnftId) public view override returns (string memory) {
        return IMetadataHandler(addressesProvider.getMetadataHandler()).getTokenURI(fnftId);
    }

    function renderTokenURI(
        uint tokenId,
        address owner
    ) public view returns (
        string memory baseRenderURI,
        string[] memory parameters
    ) {
        return IMetadataHandler(addressesProvider.getMetadataHandler()).getRenderTokenURI(tokenId, owner);
    }

}
