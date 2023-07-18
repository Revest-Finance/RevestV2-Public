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
import "./interfaces/IAllowanceTransfer.sol";
import "./interfaces/IMetadataHandler.sol";
import "./interfaces/IControllerExtendable.sol";

import "./lib/IWETH.sol";

/**
 * @title Revest_base
 * @author 0xTraub
 */
abstract contract Revest_base is IRevest, IControllerExtendable, ERC1155Holder, ReentrancyGuard, Ownable {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;
    using ERC165Checker for address;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    bytes4 public constant ERC721_INTERFACE_ID = type(IERC721).interfaceId;

    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address immutable WETH;
    ITokenVault immutable tokenVault;
    IMetadataHandler public metadataHandler;

    address public immutable ADDRESS_THIS;
    bytes4 public constant WITHDRAW_SELECTOR = bytes4(keccak256("implementSmartWalletWithdrawal(bytes)"));

    //Was deployed to same address on every chain
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    mapping(bytes32 => FNFTConfig) public fnfts;
    mapping(address handler => mapping(uint256 nftId => uint32 numfnfts)) public override numfnfts;

    constructor(address weth, address _tokenVault, address _metadataHandler, address govController) Ownable() {
        WETH = weth;
        tokenVault = ITokenVault(_tokenVault);
        metadataHandler = IMetadataHandler(_metadataHandler);

        _transferOwnership(govController);

        ADDRESS_THIS = address(this);
    }

    modifier onlyDelegateCall() {
        require(address(this) != ADDRESS_THIS, "E028");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    IResonate Functions
    //////////////////////////////////////////////////////////////*/

    function unlockFNFT(bytes32 salt) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        bytes32 lockId = keccak256(abi.encode(salt, address(this)));

        // Works for all lock types
        ILockManager(fnft.lockManager).unlockFNFT(lockId, fnft.fnftId);

        emit FNFTUnlocked(msg.sender, fnft.fnftId);
    }

    /*//////////////////////////////////////////////////////////////
                    IResonate Functions
    //////////////////////////////////////////////////////////////*/

    function mintTimeLockWithPermit(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable nonReentrant returns (bytes32 salt, bytes32 lockId) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        require(_signature.length != 0, "E024");
        PERMIT2.permit(msg.sender, permits, _signature);
        return _mintTimeLock(endTime, recipients, quantities, depositAmount, fnftConfig, true);
    }

    function mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable virtual nonReentrant returns (bytes32 salt, bytes32 lockId) {
        return _mintTimeLock(endTime, recipients, quantities, depositAmount, fnftConfig, false);
    }

    function mintAddressLockWithPermit(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable virtual nonReentrant returns (bytes32 salt, bytes32 lockId) {
        //Length check means to use permit2 for allowance but allowance has already been granted
        require(_signature.length != 0, "E024");
        PERMIT2.permit(msg.sender, permits, _signature);
        return _mintAddressLock(arguments, recipients, quantities, depositAmount, fnftConfig, true);
    }

    function mintAddressLock(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable virtual nonReentrant returns (bytes32 salt, bytes32 lockId) {
        return _mintAddressLock(arguments, recipients, quantities, depositAmount, fnftConfig, false);
    }

    function _mintAddressLock(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal virtual returns (bytes32 salt, bytes32 lockId);

    function _mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal virtual returns (bytes32 salt, bytes32 lockId);

    /*//////////////////////////////////////////////////////////////
                    IController Extendable Functions
    //////////////////////////////////////////////////////////////*/
    function depositAdditionalToFNFT(bytes32 salt, uint256 amount) external payable virtual returns (uint256 deposit) {
        return _depositAdditionalToFNFT(salt, amount, false);
    }

    function depositAdditionalToFNFTWithPermit(
        bytes32 salt,
        uint256 amount,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external virtual returns (uint256 deposit) {
        require(_signature.length != 0, "E024");
        PERMIT2.permit(msg.sender, permits, _signature);
        return _depositAdditionalToFNFT(salt, amount, true);
    }

    function _depositAdditionalToFNFT(bytes32 salt, uint256 amount, bool usePermit2)
        internal
        virtual
        returns (uint256 deposit);

    /*//////////////////////////////////////////////////////////////
                    Proxy Call Internal Functions
    //////////////////////////////////////////////////////////////*/

    function _proxyCall(
        bytes32 salt,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        address lockManager,
        address asset
    ) internal returns (bytes[] memory) {
        require(targets.length == values.length && targets.length == calldatas.length, "E026");
        require(ILockManager(lockManager).proxyCallisApproved(asset, targets, values, calldatas), "E013");

        return tokenVault.proxyCall(salt, targets, values, calldatas);
    }

    /*//////////////////////////////////////////////////////////////
                    Smart Wallet DelegateCall Functions
    //////////////////////////////////////////////////////////////*/

    function implementSmartWalletWithdrawal(bytes calldata data) external onlyDelegateCall {
        //Function is only callable via delegate-call from smart wallet
        (address transferAsset, uint256 amountToWithdraw, address recipient) =
            abi.decode(data, (address, uint256, address));

        ERC20(transferAsset).safeTransfer(recipient, amountToWithdraw);
    }

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

    function getLock(bytes32 fnftId) external view virtual returns (ILockManager.Lock memory) {
        bytes32 lockId = keccak256(abi.encode(fnftId, address(this)));

        return ILockManager(fnfts[fnftId].lockManager).getLock(lockId);
    }

    /*//////////////////////////////////////////////////////////////
                        Metadata
    //////////////////////////////////////////////////////////////*/
    function getTokenURI(bytes32 fnftId) public view returns (string memory) {
        return metadataHandler.getTokenURI(fnftId);
    }

    function renderTokenURI(bytes32 tokenId, address owner)
        public
        view
        returns (string memory baseRenderURI, string[] memory parameters)
    {
        return metadataHandler.getRenderTokenURI(tokenId, owner);
    }

    /*//////////////////////////////////////////////////////////////
                        OnlyOwner
    //////////////////////////////////////////////////////////////*/

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
