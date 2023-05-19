// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/utils/FixedPointMathLib.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IOutputReceiver.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IAddressLock.sol";
import "./interfaces/IAllowanceTransfer.sol";

import "./Revest_base.sol";

import "./lib/IWETH.sol";

import "forge-std/console2.sol";

/**
 * This is the entrypoint for the frontend, as well as third-party Revest integrations.
 * Solidity style guide ordering: receive, fallback, external, public, internal, private - within a grouping, view and pure go last - https://docs.soliditylang.org/en/latest/style-guide.html
 */
contract Revest_1155 is Revest_base {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;
    using ERC165Checker for address;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(address weth, address _tokenVault) Revest_base(weth, _tokenVault) {}

    /**
     * @dev creates a single time-locked NFT with <quantity> number of copies with <amount> of <asset> stored for each copy
     * asset - the address of the underlying ERC20 token for this bond
     * amount - the amount to store per NFT if multiple NFTs of this variety are being created
     * unlockTime - the timestamp at which this will unlock
     * quantity – the number of FNFTs to create with this operation
     */
    function _mintTimeLock(
        uint256 fnftId,
        uint256 endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal override returns (bytes32 salt, bytes32 lockId) {
        uint256 nonce;

        fnftId = IFNFTHandler(fnftConfig.handler).getNextId();

        // Get or create lock based on time, assign lock to ID
        {
            salt = keccak256(abi.encode(fnftId, fnftConfig.handler, nonce));

            require(fnfts[salt].quantity == 0, "E006");

            console2.log("---LockSalt---");
            console2.logBytes32(lockSalt);

            if (!ILockManager(fnftConfig.lockManager).lockExists(lockSalt)) {
                console2.log("creating new lock");
                IRevest.LockParam memory timeLock;
                timeLock.lockType = IRevest.LockType.TimeLock;
                timeLock.timeLockExpiry = endTime;

                lockId = ILockManager(fnftConfig.lockManager).createLock(salt, timeLock);
                fnftConfig.lockId = lockId;
            } else {
                console2.log("lock already exists");
                lockId = lockSalt;
                fnftConfig.lockId = lockSalt;
            }
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(fnftId, nonce, endTime, recipients, quantities, fnftConfig, usePermit2));

        //TODO: Fix Events
        emit FNFTTimeLockMinted(fnftConfig.asset, msg.sender, fnftId, endTime, quantities, fnftConfig);
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
    ) internal override returns (bytes32 salt, bytes32 lockId) {
        uint256 nonce;

        //If the handler is the Revest FNFT Contract get the new FNFT ID
        fnftId = IFNFTHandler(fnftConfig.handler).getNextId();

        {
            salt = keccak256(abi.encode(fnftId, fnftConfig.handler, nonce));
            require(fnfts[salt].quantity == 0, "E006"); //TODO: Double check that Error code

            if (!ILockManager(fnftConfig.lockManager).lockExists(lockSalt)) {
                IRevest.LockParam memory addressLock;
                addressLock.addressLock = trigger;
                addressLock.lockType = IRevest.LockType.AddressLock;

                //Return the ID of the lock
                lockId = ILockManager(fnftConfig.lockManager).createLock(salt, addressLock);
                fnftConfig.lockId = lockId;

                console2.log("---LockID at Creation---");
                console2.logBytes32(lockId);

                // The lock ID is already incremented prior to calling a method that could allow for reentry
                if (trigger.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)) {
                    IAddressLock(trigger).createLock(fnftId, uint256(lockId), arguments);
                }
            } else {
                lockId = lockSalt;
                fnftConfig.lockId = lockSalt;
            }
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(fnftId, nonce, 0, recipients, quantities, fnftConfig, usePermit2));

        emit FNFTAddressLockMinted(fnftConfig.asset, msg.sender, fnftId, trigger, quantities, fnftConfig);
    }

    function withdrawFNFT(bytes32 salt, uint256 quantity) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Check if this many FNFTs exist in the first place for the given ID
        require(fnft.quantity != 0, "E003");

        // Burn the FNFTs being exchanged
        IFNFTHandler(fnft.handler).burn(msg.sender, fnft.fnftId, quantity);

        console2.log("quantity: ", quantity);
        console2.log("fnftId: ", fnft.fnftId);

        //Checks-effects because unlockFNFT has an external call which could be used for reentrancy
        fnfts[salt].quantity -= quantity;

        ILockManager(fnft.lockManager).unlockFNFT(fnft.lockId, fnft.fnftId, msg.sender);

        withdrawToken(salt, fnft.fnftId, quantity, msg.sender);

        emit FNFTWithdrawn(msg.sender, fnft.fnftId, fnft.quantity);
    }

    function extendFNFTMaturity(bytes32 salt, uint256 endTime)
        external
        override
        nonReentrant
        returns (bytes32 newLockId)
    {
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        uint256 fnftId = fnft.fnftId;
        address handler = fnft.handler;

        //Require that the FNFT exists
        require(fnft.quantity != 0);

        require(endTime > block.timestamp, "E007");

        IFNFTHandler fnftHandler = IFNFTHandler(handler);

        require(fnftId < fnftHandler.getNextId(), "E003");

        uint256 supply = fnftHandler.totalSupply(fnftId);

        uint256 balance = fnftHandler.balanceOf(msg.sender, fnftId);

        //To extend the maturity you must own the entire supply so you can't extend someone eles's lock time
        require(supply != 0 && balance == supply, "E008");

        ILockManager manager = ILockManager(fnft.lockManager);

        // If it can't have its maturity extended, revert
        // Will also return false on non-time lock locks
        require(fnft.maturityExtension && manager.lockTypes(fnft.lockId) == IRevest.LockType.TimeLock, "E009");

        // If desired maturity is below existing date, reject operation
        IRevest.Lock memory lockParam = manager.getLock(fnft.lockId);
        require(!lockParam.unlocked && lockParam.timeLockExpiry > block.timestamp, "E007");
        require(lockParam.timeLockExpiry < endTime, "E010");

        // Update the lock
        IRevest.LockParam memory lock;
        lock.lockType = IRevest.LockType.TimeLock;
        lock.timeLockExpiry = endTime;

        newLockId = manager.createLock(keccak256(abi.encode(block.timestamp, endTime, msg.sender)), lock);
        fnfts[salt].lockId = newLockId;

        // Callback to IOutputReceiverV3
        if (fnft.pipeToContract != address(0) && fnft.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(fnft.pipeToContract).handleTimelockExtensions(fnftId, endTime, msg.sender);
        }

        emit FNFTMaturityExtended(newLockId, msg.sender, fnftId, endTime);
    }

    /**
     * Amount will be per FNFT. So total ERC20s needed is amount * quantity.
     * We don't charge an ETH fee on depositAdditional, but do take the erc20 percentage.
     */
    function _depositAdditionalToFNFT(bytes32 salt, uint256 amount, bool usePermit2)
        internal
        override
        returns (uint256 deposit)
    {
        IRevest.FNFTConfig storage fnft = fnfts[salt];
        uint256 fnftId = fnft.fnftId;
        address handler = fnft.handler;

        require(fnft.quantity != 0);
        require(fnftId < IFNFTHandler(handler).getNextId(), "E003");

        uint256 supply = IFNFTHandler(handler).totalSupply(fnftId);

        address smartWallet = getAddressForFNFT(salt);

        fnft.depositAmount += amount;

        deposit = supply * amount;

        // Transfer to the smart wallet
        if (fnft.asset != address(0) && amount != 0) {
            if (usePermit2) {
                PERMIT2.transferFrom(msg.sender, smartWallet, deposit.toUint160(), fnft.asset);
            } else {
                ERC20(fnft.asset).safeTransferFrom(msg.sender, smartWallet, deposit);
            }

            emit DepositERC20(fnft.asset, msg.sender, fnftId, amount, smartWallet);
        } //if (amount != zero)

        //You don't need to check for address(0) since address(0) does not include support interface
        if (fnft.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(fnft.pipeToContract).handleAdditionalDeposit(fnftId, deposit, supply, msg.sender);
        }

        emit FNFTAddionalDeposited(msg.sender, fnftId, supply, amount);
    }

    //
    // INTERNAL FUNCTIONS
    //
    function doMint(IRevest.MintParameters memory params) internal {
        bytes32 salt = keccak256(abi.encode(params.fnftId, params.fnftConfig.handler, params.nonce));

        bool isSingular;
        uint256 totalQuantity;
        {
            require(params.recipients.length == params.quantities.length, "E011");
            // Calculate total quantity
            isSingular = params.quantities.length == 1;
            if (!isSingular) {
                for (uint256 i = 0; i < params.quantities.length; i++) {
                    totalQuantity += params.quantities[i];
                }
            } else {
                totalQuantity = params.quantities[0];
            }

            require(totalQuantity > 0, "E012");
        }

        address smartWallet = getAddressForFNFT(salt);

        // Take fees
        if (msg.value != 0) {
            params.fnftConfig.asset = address(0);
            params.fnftConfig.depositAmount = msg.value / totalQuantity;
            require(msg.value / totalQuantity != 0, "E026");
            params.fnftConfig.useETH = true;
            IWETH(WETH).deposit{value: msg.value}(); //Convert it to WETH and send it back to this
            IWETH(WETH).transfer(smartWallet, msg.value); //Transfer it to the smart wallet
        } else if (params.usePermit2) {
            PERMIT2.transferFrom(
                msg.sender,
                smartWallet,
                (totalQuantity * params.fnftConfig.depositAmount).toUint160(),
                params.fnftConfig.asset
            );
        } else {
            ERC20(params.fnftConfig.asset).safeTransferFrom(
                msg.sender, smartWallet, totalQuantity * params.fnftConfig.depositAmount
            );
        }

        createFNFT(salt, params.fnftId, params.fnftConfig.handler, params.nonce, params.fnftConfig, totalQuantity);

        //Mint FNFTs but only if the handler is the Revest FNFT Handler
        if (isSingular) {
            IFNFTHandler(params.fnftConfig.handler).mint(params.recipients[0], params.fnftId, params.quantities[0], "");
        } else {
            IFNFTHandler(params.fnftConfig.handler).mint(address(this), params.fnftId, totalQuantity, "");
            for (uint256 x = 0; x < params.recipients.length;) {
                IFNFTHandler(params.fnftConfig.handler).safeTransferFrom(
                    address(this), params.recipients[x], params.fnftId, params.quantities[x], ""
                );

                unchecked {
                    ++x; //Gas Saver
                }
            }
        }

        emit CreateFNFT(salt, params.fnftId, msg.sender);
    }

    function withdrawToken(bytes32 salt, uint256 fnftId, uint256 quantity, address user) internal {
        // If the FNFT is an old one, this just assigns to zero-value
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        address pipeTo = fnft.pipeToContract;
        uint256 amountToWithdraw;

        address asset = fnft.asset == address(0) ? WETH : fnft.asset;

        address smartWalletAddr = getAddressForFNFT(salt);

        uint256 supplyBefore = IFNFTHandler(fnft.handler).totalSupply(fnftId) + quantity;

        amountToWithdraw = quantity.mulDivDown(IERC20(asset).balanceOf(smartWalletAddr), supplyBefore);

        // Deploy the smart wallet object
        address destination = (pipeTo == address(0)) ? user : pipeTo;

        tokenVault.withdrawToken(salt, asset, amountToWithdraw, address(this));

        if (asset == WETH) {
            IWETH(WETH).withdraw(amountToWithdraw);
            destination.safeTransferETH(amountToWithdraw);
        } else {
            ERC20(asset).safeTransfer(destination, amountToWithdraw);
        }

        emit WithdrawERC20(asset, user, fnftId, amountToWithdraw, smartWalletAddr);

        if (pipeTo.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(pipeTo).receiveRevestOutput(fnftId, asset, payable(user), quantity);
        }

        emit RedeemFNFT(salt, fnftId, user);
    }

    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
        external
        returns (bytes[] memory)
    {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        IFNFTHandler FNFTHandler = IFNFTHandler(fnft.handler);

        //You Must own the entire supply to call a function on the FNFT
        uint256 supply = FNFTHandler.totalSupply(fnft.fnftId);
        require(supply != 0 && FNFTHandler.balanceOf(msg.sender, fnft.fnftId) == supply, "E007");

        require(ILockManager(fnft.lockManager).proxyCallisApproved(salt, fnft.asset, targets, values, calldatas));

        return tokenVault.proxyCall(salt, targets, values, calldatas);
    }
}
