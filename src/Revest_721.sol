// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/utils/FixedPointMathLib.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IAddressLock.sol";
import "./interfaces/IAllowanceTransfer.sol";

import "./Revest_base.sol";

import "./lib/IWETH.sol";

import "forge-std/console.sol";

/**
 * This is the entrypoint for the frontend, as well as third-party Revest integrations.
 * Solidity style guide ordering: receive, fallback, external, public, internal, private - within a grouping, view and pure go last - https://docs.soliditylang.org/en/latest/style-guide.html
 */
contract Revest_721 is Revest_base {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;
    using ERC165Checker for address;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(address weth, address _tokenVault, address _metadataHandler)
        Revest_base(weth, _tokenVault, _metadataHandler)
    {}

    /**
     * @dev creates a single time-locked NFT with <quantity> number of copies with <amount> of <asset> stored for each copy
     * asset - the address of the underlying ERC20 token for this bond
     * amount - the amount to store per NFT if multiple NFTs of this variety are being created
     * unlockTime - the timestamp at which this will unlock
     * quantity – the number of FNFTs to create with this operation
     */
    function _mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal override returns (bytes32 salt, bytes32 lockId) {
        require(fnftConfig.handler.supportsInterface(ERC721_INTERFACE_ID), "E001");

        //Each NFT for a handler as an identifier, so that you can mint multiple fnfts to the same nft
        fnftConfig.nonce = numfnfts[fnftConfig.handler][fnftConfig.fnftId]++;

        // Get or create lock based on time, assign lock to ID
        {
            salt = keccak256(abi.encode(fnftConfig.fnftId, fnftConfig.handler, fnftConfig.nonce));

            //Can only be triggered by inadvertent hash collision
            require(fnfts[salt].quantity == 0, "E005");

            if (!ILockManager(fnftConfig.lockManager).lockExists(fnftConfig.lockId)) {
                ILockManager.LockParam memory timeLock;
                timeLock.lockType = ILockManager.LockType.TimeLock;
                timeLock.timeLockExpiry = endTime;
                lockId = ILockManager(fnftConfig.lockManager).createLock(salt, timeLock);

                fnftConfig.lockId = lockId;
            }
        }

        lockId = fnftConfig.lockId;

        //Stack Too Deep Fixer
        doMint(MintParameters(endTime, recipients, quantities, fnftConfig, usePermit2));

        //TODO: Fix Events
        emit FNFTTimeLockMinted(fnftConfig.asset, msg.sender, fnftConfig.fnftId, endTime, quantities, fnftConfig);
    }

    function _mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal override returns (bytes32 salt, bytes32 lockId) {
        require(fnftConfig.handler.supportsInterface(ERC721_INTERFACE_ID), "E001");

        //Each NFT for a handler as an identifier, so that you can mint multiple fnfts to the same nft
        fnftConfig.nonce = numfnfts[fnftConfig.handler][fnftConfig.fnftId]++;

        {
            salt = keccak256(abi.encode(fnftConfig.fnftId, fnftConfig.handler, fnftConfig.nonce));

            //Impossible to trigger manually, only be hash collision, but just in case
            require(fnfts[salt].quantity == 0, "E005");

            if (!ILockManager(fnftConfig.lockManager).lockExists(fnftConfig.lockId)) {
                ILockManager.LockParam memory addressLock;
                addressLock.addressLock = trigger;
                addressLock.lockType = ILockManager.LockType.AddressLock;

                //Return the ID of the lock
                lockId = ILockManager(fnftConfig.lockManager).createLock(salt, addressLock);

                // The lock ID is already incremented prior to calling a method that could allow for reentry
                if (trigger.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)) {
                    IAddressLock(trigger).createLock(fnftConfig.fnftId, uint256(lockId), arguments);
                }

                fnftConfig.lockId = lockId;
            }
        }

        lockId = fnftConfig.lockId;

        //Stack Too Deep Fixer
        doMint(MintParameters(0, recipients, quantities, fnftConfig, usePermit2));

        emit FNFTAddressLockMinted(fnftConfig.asset, msg.sender, fnftConfig.fnftId, trigger, quantities, fnftConfig);
    }

    function withdrawFNFT(bytes32 salt, uint256) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Check if this many FNFTs exist in the first place for the given ID
        require(fnft.quantity > 0, "E003");

        address currentOwner = IERC721(fnft.handler).ownerOf(fnft.fnftId);
        require(msg.sender == currentOwner, "E023");

        fnfts[salt].quantity -= 1;

        ILockManager(fnft.lockManager).unlockFNFT(fnft.lockId, fnft.fnftId);

        withdrawToken(salt, fnft.fnftId, currentOwner);

        emit FNFTWithdrawn(currentOwner, fnft.fnftId, 1);
    }

    /// @return the FNFT ID
    function extendFNFTMaturity(bytes32 salt, uint256 endTime) external override nonReentrant returns (bytes32) {
        IRevest.FNFTConfig storage fnft = fnfts[salt];
        uint256 fnftId = fnft.fnftId;
        address handler = fnft.handler;

        //Require that the FNFT exists
        require(fnft.quantity != 0, "E003");

        //Require that the new maturity is in the future
        require(endTime > block.timestamp, "E015");

        //Only the NFT owner can extend the lock on the NFT
        require(IERC721(handler).ownerOf(fnftId) == msg.sender, "E023");

        ILockManager manager = ILockManager(fnft.lockManager);

        // If it can't have its maturity extended, revert
        // Will also return false on non-time lock locks
        require(fnft.maturityExtension && manager.lockTypes(fnft.lockId) == ILockManager.LockType.TimeLock, "E009");

        // If desired maturity is below existing date or already unlocked, reject operation
        ILockManager.Lock memory lockParam = manager.getLock(fnft.lockId);

        require(!lockParam.unlocked && lockParam.timeLockExpiry > block.timestamp, "E007");

        console.log("original end time: %i", lockParam.timeLockExpiry);
        console.log("new end time: %i", endTime);

        require(lockParam.timeLockExpiry < endTime, "E010");

        // Update the lock
        ILockManager.LockParam memory lock;
        lock.lockType = ILockManager.LockType.TimeLock;
        lock.timeLockExpiry = endTime;

        //Just pick a salt, it doesn't matter as long as it's unique
        bytes32 newLockId = manager.createLock(keccak256(abi.encode(block.timestamp, endTime, msg.sender)), lock);
        fnft.lockId = newLockId;

        emit FNFTMaturityExtended(newLockId, msg.sender, fnftId, endTime);

        return newLockId;
    }

    /**
     * Amount will be per FNFT. So total ERC20s needed is amount * quantity.
     * We don't charge an ETH fee on depositAdditional, but do take the erc20 percentage.
     */
    function _depositAdditionalToFNFT(bytes32 salt, uint256 amount, bool usePermit2)
        internal
        override
        returns (uint256)
    {
        IRevest.FNFTConfig storage fnft = fnfts[salt];
        uint256 fnftId = fnft.fnftId;

        fnft.depositAmount += amount;

        require(fnft.quantity != 0, "E003");

        //If the handler is an NFT then supply is 1

        bytes32 walletSalt = keccak256(abi.encode(fnft.fnftId, fnft.handler));
        address smartWallet = tokenVault.getAddress(walletSalt, address(this));

        // Transfer to the smart wallet
        if (fnft.asset != address(0xdead) && amount != 0) {
            if (usePermit2) {
                console.log("amount to deposit: %i", amount);
                PERMIT2.transferFrom(msg.sender, smartWallet, amount.toUint160(), fnft.asset);
            } else {
                ERC20(fnft.asset).safeTransferFrom(msg.sender, smartWallet, amount);
            }

            emit DepositERC20(fnft.asset, msg.sender, fnftId, amount, smartWallet);
        } else {
            require(msg.value == amount, "E027");

            IWETH(WETH).deposit{value: msg.value}();

            ERC20(WETH).safeTransfer(smartWallet, msg.value);
        }

        emit FNFTAddionalDeposited(msg.sender, fnftId, 1, amount);

        return amount;
    }

    //
    // INTERNAL FUNCTIONS
    //
    function doMint(IRevest.MintParameters memory params) internal {
        //fnftSalt is the identifier for FNFT itself associated with the NFT, you need it to withdraw
        bytes32 fnftSalt =
            keccak256(abi.encode(params.fnftConfig.fnftId, params.fnftConfig.handler, params.fnftConfig.nonce));

        /*
        * Wallet salt is used to generate the wallet. All FNFTs attached to a given NFT have their tokens stored in the same address.
        * This is because the NFT is the identifier for the vault, and the FNFT is the identifier for the token within the vault.
        * and since every FNFT has a difference nonce we need to remove it from the salt to be able to generate the same address
        */
        bytes32 WalletSalt = keccak256(abi.encode(params.fnftConfig.fnftId, params.fnftConfig.handler));
       

        // Create the FNFT and update accounting within TokenVault
        params.fnftConfig.quantity = 1;

        // Now, we move the funds to token vault from the message sender
        address smartWallet = tokenVault.getAddress(WalletSalt, address(this));


        if (msg.value != 0) {
            params.fnftConfig.asset = address(0xdead);
            params.fnftConfig.depositAmount = msg.value;
            params.fnftConfig.useETH = true;
            IWETH(WETH).deposit{value: msg.value}(); //Convert it to WETH and send it back to this
            IWETH(WETH).transfer(smartWallet, msg.value); //Transfer it to the smart wallet
        } else if (params.usePermit2) {
            PERMIT2.transferFrom(
                msg.sender, smartWallet, (params.fnftConfig.depositAmount).toUint160(), params.fnftConfig.asset
            );
        } else {
            ERC20(params.fnftConfig.asset).safeTransferFrom(msg.sender, smartWallet, params.fnftConfig.depositAmount);
        }

        fnfts[fnftSalt] = params.fnftConfig;

        emit CreateFNFT(fnftSalt, params.fnftConfig.fnftId, msg.sender);
    }

    function withdrawToken(bytes32 salt, uint256 fnftId, address user) internal {
        // If the FNFT is an old one, this just assigns to zero-value
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        uint256 amountToWithdraw;

        //When the user deposits Eth it stores the asset as address(0xdead) but actual WETH is kept in the vault
        address transferAsset = fnft.asset == address(0xdead) ? WETH : fnft.asset;

        bytes32 walletSalt = keccak256(abi.encode(fnftId, fnft.handler));

        address smartWallAdd = tokenVault.getAddress(walletSalt, address(this));

        amountToWithdraw = IERC20(transferAsset).balanceOf(smartWallAdd);
        console.log("amount to withdraw: %i", amountToWithdraw);

        // Deploy the smart wallet object

        tokenVault.withdrawToken(walletSalt, transferAsset, amountToWithdraw, address(this));

        if (fnft.asset == address(0xdead)) {
            IWETH(WETH).withdraw(amountToWithdraw);
            user.safeTransferETH(amountToWithdraw);
        } else {
            ERC20(fnft.asset).safeTransfer(user, amountToWithdraw);
        }

        emit WithdrawERC20(transferAsset, user, fnftId, amountToWithdraw, smartWallAdd);

        emit RedeemFNFT(salt, fnftId, user);
    }

    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
        external
        returns (bytes[] memory)
    {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        //Only the NFT owner can call a function on the NFT
        require(IERC721(fnft.handler).ownerOf(fnft.fnftId) == msg.sender, "E023");

        bytes32 walletSalt = keccak256(abi.encode(fnft.fnftId, fnft.handler));

        return _proxyCall(walletSalt, targets, values, calldatas, fnft.lockManager, fnft.asset);
    }

    //Takes in an FNFT Salt and generates a wallet salt from it
    function getAddressForFNFT(bytes32 salt) public view virtual returns (address smartWallet) {
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        bytes32 walletSalt = keccak256(abi.encode(fnft.fnftId, fnft.handler));

        smartWallet = tokenVault.getAddress(walletSalt, address(this));
    }
}
