// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/utils/FixedPointMathLib.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IOutputReceiver.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IAddressLock.sol";
import "./interfaces/IAllowanceTransfer.sol";

import "./lib/IWETH.sol";

import "forge-std/console2.sol";

/**
 * This is the entrypoint for the frontend, as well as third-party Revest integrations.
 * Solidity style guide ordering: receive, fallback, external, public, internal, private - within a grouping, view and pure go last - https://docs.soliditylang.org/en/latest/style-guide.html
 */
abstract contract Revest_base is IRevest, ERC1155Holder, ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;
    using ERC165Checker for address;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    bytes4 public constant ADDRESS_LOCK_INTERFACE_ID = type(IAddressLock).interfaceId;
    bytes4 public constant OUTPUT_RECEIVER_INTERFACE_ID = type(IOutputReceiver).interfaceId;
    bytes4 public constant FNFTHANDLER_INTERFACE_ID = type(IFNFTHandler).interfaceId;
    bytes4 public constant ERC721_INTERFACE_ID = type(IERC721).interfaceId;

    address immutable WETH;
    ITokenVault immutable tokenVault;

    //Deployed omni-chain to same address
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(bytes32 => FNFTConfig) public fnfts;
    mapping(address handler => mapping(uint256 nftId => uint256 numfnfts)) public override numfnfts;
    mapping(bytes4 selector => bool blackListed) public override blacklistedFunctions;

    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(address weth, address _tokenVault) Ownable() {
        WETH = weth;
        tokenVault = ITokenVault(_tokenVault);
    }

    function mintTimeLockWithPermit(
        uint256 fnftId,
        uint256 endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        if (_signature.length != 0) PERMIT2.permit(msg.sender, permits, _signature);
        return _mintTimeLock(fnftId, endTime, lockSalt, recipients, quantities, fnftConfig, true);
    }

    function mintTimeLock(
        uint256 fnftId,
        uint256 endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable virtual override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        return _mintTimeLock(fnftId, endTime, lockSalt, recipients, quantities, fnftConfig, false);
    }

    function mintAddressLockWithPermit(
        uint256 fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable virtual override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        if (_signature.length != 0) PERMIT2.permit(msg.sender, permits, _signature);
        return _mintAddressLock(fnftId, trigger, lockSalt, arguments, recipients, quantities, fnftConfig, true);
    }

    function mintAddressLock(
        uint256 fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable virtual override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        return _mintAddressLock(fnftId, trigger, lockSalt, arguments, recipients, quantities, fnftConfig, false);
    }

    function _mintAddressLock(
        uint256 fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal virtual returns (bytes32 salt, bytes32 lockId);

    function _mintTimeLock(
        uint256 fnftId,
        uint256 endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal virtual returns (bytes32 salt, bytes32 lockId);

    /// Advanced FNFT withdrawals removed for the time being – no active implementations
    /// Represents slightly increased surface area – may be utilized in Resolve

    function unlockFNFT(bytes32 salt) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Works for value locks or time locks
        ILockManager(fnft.lockManager).unlockFNFT(fnft.lockId, fnft.fnftId, msg.sender);

        //TODO: Fix Events
        emit FNFTUnlocked(msg.sender, fnft.fnftId);
    }

    function depositAdditionalToFNFT(bytes32 salt, uint256 amount) external virtual returns (uint256 deposit) {
        return _depositAdditionalToFNFT(salt, amount, false);
    }

    function depositAdditionalToFNFTWithPermit(
        bytes32 salt,
        uint256 amount,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external virtual returns (uint256 deposit) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        if (_signature.length != 0) PERMIT2.permit(msg.sender, permits, _signature);
        return _depositAdditionalToFNFT(salt, amount, true);
    }

    function _depositAdditionalToFNFT(bytes32 salt, uint256 amount, bool usePermit2)
        internal
        virtual
        returns (uint256 deposit);

    function createFNFT(
        bytes32 salt,
        uint256 fnftId,
        address handler,
        uint256 nonce,
        IRevest.FNFTConfig memory fnftConfig,
        uint256 quantity
    ) internal virtual {
        fnfts[salt] = fnftConfig;

        fnfts[salt].nonce = nonce;
        fnfts[salt].fnftId = fnftId;
        fnfts[salt].handler = handler;
        fnfts[salt].quantity = quantity;
    } //createFNFT

    //You don't need this but it makes it a little easier to return an object and not a bunch of variables
    function getFNFT(bytes32 fnftId) external view virtual returns (IRevest.FNFTConfig memory) {
        return fnfts[fnftId];
    }

    function changeSelectorVisibility(bytes4 selector, bool designation) external virtual onlyOwner {
        blacklistedFunctions[selector] = designation;
    }

    function transferOwnershipFNFTHandler(address newRevest, address handler) external virtual onlyOwner {
        //Ownership should be a timelocked controller.
        Ownable(handler).transferOwnership(newRevest);
    }

    function getAddressForFNFT(bytes32 salt) public view virtual returns (address smartWallet) {
        smartWallet = tokenVault.getAddress(salt, address(this));
    }

    receive() external payable {
        //Do Nothing but receive
    }

    fallback() external payable {
        //Do Nothing but receive
    }
}
