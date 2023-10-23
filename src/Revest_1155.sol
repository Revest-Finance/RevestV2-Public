// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import { FNFTHandler } from "./FNFTHandler.sol";

import "./Revest_base.sol";

/**
 * @title Revest_1155
 * @author 0xTraub
 */
contract Revest_1155 is Revest_base {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;
    using ERC165Checker for address;
    using FixedPointMathLib for uint256;
    using SafeCast for uint256;

    IFNFTHandler public immutable fnftHandler;

    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(
        string memory tokenURI,
        address weth,
        address _tokenVault,
        address _metadataHandler,
        address govController
    ) Revest_base(weth, _tokenVault, _metadataHandler, govController) {
        fnftHandler = new FNFTHandler(tokenURI, govController);
    }

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
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal override returns (uint fnftId, bytes32 lockId) {
        //You can safely cast this since getNextId is an incrementing variable
        fnftId = fnftHandler.getNextId();

        // Get or create lock based on time, assign lock to ID
        {
            //Salt = kecccak256(fnftID)
            bytes32 salt = keccak256(abi.encode(fnftId));

            lockId = ILockManager(fnftConfig.lockManager).createLock(salt, abi.encode(endTime));
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(endTime, recipients, quantities, depositAmount, fnftId, fnftConfig, usePermit2));

        emit FNFTTimeLockMinted(fnftConfig.asset, msg.sender, fnftId, endTime, quantities, fnftConfig);
    }

    function _mintAddressLock(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal override returns (uint fnftId, bytes32 lockId) {
        //Get the ID of the next to-be-minted FNFT
        fnftId = fnftHandler.getNextId();

        {
            //Salt = kecccak256(fnftID || handler || nonce (which is always zero))
            bytes32 salt = keccak256(abi.encode(fnftId));

            //Return the ID of the lock
            lockId = ILockManager(fnftConfig.lockManager).createLock(salt, arguments);
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(0, recipients, quantities, depositAmount, fnftId, fnftConfig, usePermit2));

        emit FNFTAddressLockMinted(fnftConfig.asset, msg.sender, fnftId, quantities, fnftConfig);
    }

    function withdrawFNFT(uint fnftId, uint256 quantity) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[fnftId];

        // Check if FNFTs exist in the first place for the given ID

        require(fnftHandler.totalSupply(fnftId) != 0, "E003");

        // Burn the FNFTs being exchanged
        fnftHandler.burn(msg.sender, fnftId, quantity);

        bytes32 lockId = fnftIdToLockId(fnftId);

        ILockManager(fnft.lockManager).unlockFNFT(lockId, fnftId);

        withdrawToken(fnftId, quantity, msg.sender);

        emit FNFTWithdrawn(msg.sender, fnftId, quantity);
    }

    function extendFNFTMaturity(uint fnftId, uint256 endTime) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[fnftId];

        //Require that the FNFT exists
        require(fnftHandler.totalSupply(fnftId) != 0, "E003");

        require(endTime > block.timestamp, "E015");

        uint256 supply = fnftHandler.totalSupply(fnftId);

        uint256 balance = fnftHandler.balanceOf(msg.sender, fnftId);

        //To extend the maturity you must own the entire supply so you can't extend someone eles's lock time
        require(supply != 0 && balance == supply, "E008");

        ILockManager manager = ILockManager(fnft.lockManager);

        // If it can't have its maturity extended, revert
        // Will also return false on non-time lock locks
        require(fnft.maturityExtension && manager.lockType() == ILockManager.LockType.TimeLock, "E009");

        bytes32 lockId = fnftIdToLockId(fnftId);
        
        // If desired maturity is below existing date, reject operation
        ILockManager.Lock memory lockParam = manager.getLock(lockId);
        require(!lockParam.unlocked && lockParam.timeLockExpiry > block.timestamp, "E007");
        require(lockParam.timeLockExpiry < endTime, "E010");

        bytes memory creationData = abi.encode(endTime);

        bytes32 lockSalt = keccak256(abi.encode(fnftId));
        manager.extendLockMaturity(lockSalt, creationData);

        emit FNFTMaturityExtended(lockId, msg.sender, fnftId, endTime);
    }

    /**
     * Amount will be per FNFT. So total ERC20s needed is amount * quantity.
     * We don't charge an ETH fee on depositAdditional, but do take the erc20 percentage.
     */
    function _depositAdditionalToFNFT(uint fnftId, uint256 amount, bool usePermit2)
        internal
        override
        returns (uint256 deposit)
    {
        IRevest.FNFTConfig storage fnft = fnfts[fnftId];

        require(fnftHandler.totalSupply(fnftId) != 0, "E003");

        uint256 supply = fnftHandler.totalSupply(fnftId);

        address smartWallet = getAddressForFNFT(fnftId);

        deposit = supply * amount;

        address depositAsset = fnft.asset;

        //Underlying is ETH, store it by wrapping to WETH first
        if (msg.value != 0 && fnft.asset == ETH_ADDRESS) {
            require(msg.value == deposit, "E027");

            IWETH(WETH).deposit{value: msg.value}();

            ERC20(WETH).safeTransfer(smartWallet, deposit);

            return deposit;
        }
        //Underlying is ETH, user wants to deposit WETH, without wrapping first
        else if (msg.value == 0 && fnft.asset == ETH_ADDRESS) {
            depositAsset = WETH;
        }

        if (usePermit2 && deposit != 0) {
            PERMIT2.transferFrom(msg.sender, smartWallet, deposit.toUint160(), depositAsset);
        } else if (deposit != 0){
            ERC20(depositAsset).safeTransferFrom(msg.sender, smartWallet, deposit);
        }

        emit FNFTAddionalDeposited(msg.sender, fnftId, supply, amount);
    }

    //
    // INTERNAL FUNCTIONS
    //
    function doMint(IRevest.MintParameters memory params) internal {
        bytes32 salt = keccak256(abi.encode(params.fnftConfig.fnftId));

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

        address smartWallet = getAddressForFNFT(params.fnftId);

        //If user depositing ETH, wrap it to WETH first
        if (msg.value != 0) {
            params.fnftConfig.asset = ETH_ADDRESS;

            //User sent enough ETH to pay for all FNFTs
            require(msg.value / totalQuantity == params.depositAmount, "E027");

            IWETH(WETH).deposit{value: msg.value}(); //Convert it to WETH and send it back to this
            IWETH(WETH).transfer(smartWallet, msg.value); //Transfer it to the smart wallet
        } else if (params.usePermit2 && params.depositAmount != 0) {
            PERMIT2.transferFrom(
                msg.sender,
                smartWallet,
                (totalQuantity * params.depositAmount).toUint160(), //permit2 uses a uint160 for the amount
                params.fnftConfig.asset
            );
        } else if (params.depositAmount != 0) {
            ERC20(params.fnftConfig.asset).safeTransferFrom(
                msg.sender, smartWallet, totalQuantity * params.depositAmount
            );
        }

        //Mint FNFTs but only if the handler is the Revest FNFT Handler
        if (isSingular) {
            fnftHandler.mint(params.recipients[0], params.fnftId, params.quantities[0], "");
        } else {
            fnftHandler.mint(address(this), params.fnftId, totalQuantity, "");
            for (uint256 x = 0; x < params.recipients.length;) {
                fnftHandler.safeTransferFrom(
                    address(this), params.recipients[x], params.fnftId, params.quantities[x], ""
                );

                unchecked {
                    ++x; //Gas Saver
                }
            }
        }

        fnfts[params.fnftId] = params.fnftConfig;

        emit CreateFNFT(params.fnftId, msg.sender);
    }

    function withdrawToken(uint256 fnftId, uint256 quantity, address destination) internal {
        // If the FNFT is an old one, this just assigns to zero-value
        IRevest.FNFTConfig memory fnft = fnfts[fnftId];
        uint256 amountToWithdraw;

        //When the user deposits Eth it stores the asset as the all E's address but actual WETH is kept in the vault
        address transferAsset = fnft.asset == ETH_ADDRESS ? WETH : fnft.asset;

        bytes32 salt = keccak256(abi.encode(fnftId));
        address smartWalletAddr = getAddressForFNFT(fnftId);

        uint256 supplyBefore = fnftHandler.totalSupply(fnftId) + quantity;

        uint256 depositAmount = IERC20(transferAsset).balanceOf(smartWalletAddr);

        amountToWithdraw = quantity.mulDivDown(depositAmount, supplyBefore);

        // Deploy the smart wallet object
        bytes memory delegateCallData = abi.encode(transferAsset, amountToWithdraw, address(this));
        tokenVault.invokeSmartWallet(salt, WITHDRAW_SELECTOR, delegateCallData);

        //Return ETH to the user or WETH
        if (fnft.asset == ETH_ADDRESS && amountToWithdraw != 0) {
            IWETH(WETH).withdraw(amountToWithdraw);
            destination.safeTransferETH(amountToWithdraw);
        } else if (amountToWithdraw != 0) {
            ERC20(fnft.asset).safeTransfer(destination, amountToWithdraw);
        }

        emit WithdrawERC20(transferAsset, destination, fnftId, amountToWithdraw, smartWalletAddr);

        emit RedeemFNFT(fnftId, destination);
    }


    function getAddressForFNFT(uint fnftId) public view virtual returns (address smartWallet) {
        smartWallet = tokenVault.getAddress(keccak256(abi.encode(fnftId)), address(this));
    }

    function getValue(uint fnftId) external view virtual returns (uint256) {
        IRevest.FNFTConfig memory fnft = fnfts[fnftId];

        uint256 supply = fnftHandler.totalSupply(fnftId);
        if (supply == 0) return 0;

        address asset = fnft.asset == ETH_ADDRESS ? WETH : fnft.asset;
        uint256 balanceOf = IERC20(asset).balanceOf(getAddressForFNFT(fnftId));

        return balanceOf / supply;
    }

    function fnftIdToRevestId(uint256 fnftId) public pure returns (bytes32 salt) {
        salt = keccak256(abi.encode(fnftId));
    }

    function fnftIdToLockId(uint256 fnftId) public view returns (bytes32 lockId) {
        bytes32 salt = keccak256(abi.encode(fnftId));

        return keccak256(abi.encode(salt, address(this)));
    }
}
