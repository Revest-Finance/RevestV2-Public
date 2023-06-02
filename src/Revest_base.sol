// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity <=0.8.19;

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
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IAddressLock.sol";
import "./interfaces/IAllowanceTransfer.sol";
import "./interfaces/IMetadataHandler.sol";
import "./interfaces/IControllerExtendable.sol";

import "./lib/IWETH.sol";

import "forge-std/console2.sol";

abstract contract Revest_base is IRevest, IControllerExtendable, ERC1155Holder, ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;
    using ERC165Checker for address;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    bytes4 public constant ADDRESS_LOCK_INTERFACE_ID = type(IAddressLock).interfaceId;
    bytes4 public constant FNFTHANDLER_INTERFACE_ID = type(IFNFTHandler).interfaceId;
    bytes4 public constant ERC721_INTERFACE_ID = type(IERC721).interfaceId;

    address immutable WETH;
    ITokenVault immutable tokenVault;
    IMetadataHandler public metadataHandler;

    //Deployed omni-chain to same address
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(bytes32 => FNFTConfig) public fnfts;
    mapping(address handler => mapping(uint256 nftId => uint256 numfnfts)) public override numfnfts;
    mapping(bytes4 selector => bool blackListed) public override blacklistedFunctions;

    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(address weth, address _tokenVault, address _metadataHandler) Ownable() {
        WETH = weth;
        tokenVault = ITokenVault(_tokenVault);
        metadataHandler = IMetadataHandler(_metadataHandler);
    }

    /*//////////////////////////////////////////////////////////////
                    IResonate Functions
    //////////////////////////////////////////////////////////////*/

    function unlockFNFT(bytes32 salt) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Works for value locks or time locks
        ILockManager(fnft.lockManager).unlockFNFT(fnft.lockId, fnft.fnftId);

        //TODO: Fix Events
        emit FNFTUnlocked(msg.sender, fnft.fnftId);
    }

    /*//////////////////////////////////////////////////////////////
                    IResonate Functions
    //////////////////////////////////////////////////////////////*/

    function mintTimeLockWithPermit(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable nonReentrant returns (bytes32 salt, bytes32 lockId) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        require(_signature.length != 0, "E024");
        PERMIT2.permit(msg.sender, permits, _signature);
        return _mintTimeLock(endTime, recipients, quantities, fnftConfig, true);
    }

    function mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable virtual nonReentrant returns (bytes32 salt, bytes32 lockId) {
        return _mintTimeLock(endTime, recipients, quantities, fnftConfig, false);
    }

    function mintAddressLockWithPermit(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable virtual nonReentrant returns (bytes32 salt, bytes32 lockId) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        require(_signature.length != 0, "E024");
        PERMIT2.permit(msg.sender, permits, _signature);
        return _mintAddressLock(trigger, arguments, recipients, quantities, fnftConfig, true);
    }

    function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable virtual nonReentrant returns (bytes32 salt, bytes32 lockId) {
        return _mintAddressLock(trigger, arguments, recipients, quantities, fnftConfig, false);
    }

    function _mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal virtual returns (bytes32 salt, bytes32 lockId);

    function _mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal virtual returns (bytes32 salt, bytes32 lockId);

    /*//////////////////////////////////////////////////////////////
                    IController Extendable Functions
    //////////////////////////////////////////////////////////////*/
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
        require(_signature.length != 0, "E024");
        PERMIT2.permit(msg.sender, permits, _signature);
        return _depositAdditionalToFNFT(salt, amount, true);
    }

    function _depositAdditionalToFNFT(bytes32 salt, uint256 amount, bool usePermit2)
        internal
        virtual
        returns (uint256 deposit);

    /*//////////////////////////////////////////////////////////////
                    IController View Functions
    //////////////////////////////////////////////////////////////*/

    //You don't need this but it makes it a little easier to return an object and not a bunch of variables from a mapping
    function getFNFT(bytes32 fnftId) external view virtual returns (IRevest.FNFTConfig memory) {
        return fnfts[fnftId];
    }

    function getAsset(bytes32 fnftId) external view virtual returns (address) {
        return fnfts[fnftId].asset;
    }

    function getValue(bytes32 fnftId) external view virtual returns (uint256) {
        return fnfts[fnftId].depositAmount;
    }

    /*//////////////////////////////////////////////////////////////
                        Metadata
    //////////////////////////////////////////////////////////////*/
    function getTokenURI(uint256 fnftId) public view returns (string memory) {
        return metadataHandler.getTokenURI(fnftId);
    }

    function renderTokenURI(uint256 tokenId, address owner)
        public
        view
        returns (string memory baseRenderURI, string[] memory parameters)
    {
        return metadataHandler.getRenderTokenURI(tokenId, owner);
    }

    /*//////////////////////////////////////////////////////////////
                        OnlyOwner
    //////////////////////////////////////////////////////////////*/
    function changeSelectorVisibility(bytes4 selector, bool designation) external virtual onlyOwner {
        blacklistedFunctions[selector] = designation;
    }

    function transferOwnershipFNFTHandler(address newRevest, address handler) external virtual onlyOwner {
        //Ownership should be a timelocked controller.
        Ownable(handler).transferOwnership(newRevest);
    }

    function changeMetadataHandler(address _newMetadataHandler) external onlyOwner {
        metadataHandler = IMetadataHandler(_newMetadataHandler);
        //TODO: Emit Event
    }

    /*//////////////////////////////////////////////////////////////
                        Fallback for Weth
    //////////////////////////////////////////////////////////////*/
    receive() external payable {
        //Do Nothing but receive
    }

    fallback() external payable {
        //Do Nothing but receive
    }
}
