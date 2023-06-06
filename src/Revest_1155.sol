// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/utils/FixedPointMathLib.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IAllowanceTransfer.sol";

import "./Revest_base.sol";

import "./lib/IWETH.sol";

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
        require(fnftConfig.handler.supportsInterface(type(IFNFTHandler).interfaceId), "E001");

        fnftConfig.fnftId = IFNFTHandler(fnftConfig.handler).getNextId();

        // Get or create lock based on time, assign lock to ID
        {
            salt = keccak256(abi.encode(fnftConfig.fnftId, fnftConfig.handler, 0));

            if (!ILockManager(fnftConfig.lockManager).lockExists(fnftConfig.lockId)) {
                lockId = ILockManager(fnftConfig.lockManager).createLock(salt, abi.encode(endTime));
                fnftConfig.lockId = lockId;
            } else {
                lockId = fnftConfig.lockId;
                fnftConfig.lockId = fnftConfig.lockId;
            }
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(endTime, recipients, quantities, fnftConfig, usePermit2));

        emit FNFTTimeLockMinted(fnftConfig.asset, msg.sender, fnftConfig.fnftId, endTime, quantities, fnftConfig);
    }

    function _mintAddressLock(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        bool usePermit2
    ) internal override returns (bytes32 salt, bytes32 lockId) {
        require(fnftConfig.handler.supportsInterface(type(IFNFTHandler).interfaceId), "E001");

        //Get the ID of the next to-be-minted FNFT
        fnftConfig.fnftId = IFNFTHandler(fnftConfig.handler).getNextId();

        {
            //Salt = kecccak256(fnftID || handler || nonce (which is always zero))
            salt = keccak256(abi.encode(fnftConfig.fnftId, fnftConfig.handler, 0));

            if (!ILockManager(fnftConfig.lockManager).lockExists(fnftConfig.lockId)) {
                //Return the ID of the lock
                lockId = ILockManager(fnftConfig.lockManager).createLock(salt, arguments);
                fnftConfig.lockId = lockId;
            } else {
                lockId = fnftConfig.lockId;
                fnftConfig.lockId = fnftConfig.lockId;
            }
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(0, recipients, quantities, fnftConfig, usePermit2));

        emit FNFTAddressLockMinted(fnftConfig.asset, msg.sender, fnftConfig.fnftId, quantities, fnftConfig);
    }

    function withdrawFNFT(bytes32 salt, uint256 quantity) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Check if FNFTs exist in the first place for the given ID
        require(fnft.quantity != 0, "E003");

        // Burn the FNFTs being exchanged
        IFNFTHandler(fnft.handler).burn(msg.sender, fnft.fnftId, quantity);

        //Checks-effects because unlockFNFT has an external call which could be used for reentrancy
        fnfts[salt].quantity -= quantity;

        ILockManager(fnft.lockManager).unlockFNFT(fnft.lockId, fnft.fnftId);

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
        require(fnft.quantity != 0, "E003");

        require(endTime > block.timestamp, "E015");

        IFNFTHandler fnftHandler = IFNFTHandler(handler);

        uint256 supply = fnftHandler.totalSupply(fnftId);

        uint256 balance = fnftHandler.balanceOf(msg.sender, fnftId);

        //To extend the maturity you must own the entire supply so you can't extend someone eles's lock time
        require(supply != 0 && balance == supply, "E008");

        ILockManager manager = ILockManager(fnft.lockManager);

        // If it can't have its maturity extended, revert
        // Will also return false on non-time lock locks
        require(fnft.maturityExtension && manager.lockType() == ILockManager.LockType.TimeLock, "E009");

        // If desired maturity is below existing date, reject operation
        ILockManager.Lock memory lockParam = manager.getLock(fnft.lockId);
        require(!lockParam.unlocked && lockParam.timeLockExpiry > block.timestamp, "E007");
        require(lockParam.timeLockExpiry < endTime, "E010");

        bytes memory creationData = abi.encode(endTime);

        newLockId = manager.createLock(keccak256(abi.encode(block.timestamp, endTime, msg.sender)), creationData);
        fnfts[salt].lockId = newLockId;

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

        require(fnft.quantity != 0, "E003");

        uint256 supply = IFNFTHandler(handler).totalSupply(fnftId);

        address smartWallet = getAddressForFNFT(salt);

        fnft.depositAmount += amount;

        deposit = supply * amount;

        address depositAsset = fnft.asset;

        //Underlying is ETH, store it by wrapping to WETH first
        if (msg.value != 0 && fnft.asset == address(0xdead)) {
            require(msg.value == deposit, "E027");

            IWETH(WETH).deposit{value: msg.value}();

            ERC20(WETH).safeTransfer(smartWallet, deposit);

            return deposit;
        }

        //Underlying is ETH, user wants to deposit WETH, without wrapping first
        else if (msg.value == 0 && fnft.asset == address(0xdead)) {
            depositAsset = WETH;
        }

        if (usePermit2) {
            PERMIT2.transferFrom(msg.sender, smartWallet, deposit.toUint160(), depositAsset);
        } else {
            ERC20(depositAsset).safeTransferFrom(msg.sender, smartWallet, deposit);
        }

        emit FNFTAddionalDeposited(msg.sender, fnftId, supply, amount);
    }

    //
    // INTERNAL FUNCTIONS
    //
    function doMint(IRevest.MintParameters memory params) internal {
        bytes32 salt =
            keccak256(abi.encode(params.fnftConfig.fnftId, params.fnftConfig.handler, params.fnftConfig.nonce));

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

        params.fnftConfig.quantity = totalQuantity;
        address smartWallet = getAddressForFNFT(salt);

        //If user depositing ETH, wrap it to WETH first
        if (msg.value != 0) {
            params.fnftConfig.asset = address(0xdead);

            //User sent enough ETH to pay for all FNFTs
            require(msg.value / totalQuantity == params.fnftConfig.depositAmount, "E027");
            params.fnftConfig.useETH = true;

            IWETH(WETH).deposit{value: msg.value}(); //Convert it to WETH and send it back to this
            IWETH(WETH).transfer(smartWallet, msg.value); //Transfer it to the smart wallet
        
        } else if (params.usePermit2) {
            PERMIT2.transferFrom(
                msg.sender,
                smartWallet,
                (totalQuantity * params.fnftConfig.depositAmount).toUint160(),//permit2 uses a uint160 for the amount
                params.fnftConfig.asset
            );
        } else {
            ERC20(params.fnftConfig.asset).safeTransferFrom(
                msg.sender, smartWallet, totalQuantity * params.fnftConfig.depositAmount
            );
        }


        //Mint FNFTs but only if the handler is the Revest FNFT Handler
        if (isSingular) {
            IFNFTHandler(params.fnftConfig.handler).mint(
                params.recipients[0], params.fnftConfig.fnftId, params.quantities[0], ""
            );
        } else {
            IFNFTHandler(params.fnftConfig.handler).mint(address(this), params.fnftConfig.fnftId, totalQuantity, "");
            for (uint256 x = 0; x < params.recipients.length;) {
                IFNFTHandler(params.fnftConfig.handler).safeTransferFrom(
                    address(this), params.recipients[x], params.fnftConfig.fnftId, params.quantities[x], ""
                );

                unchecked {
                    ++x; //Gas Saver
                }
            }
        }

        fnfts[salt] = params.fnftConfig;

        emit CreateFNFT(salt, params.fnftConfig.fnftId, msg.sender);
    }

    function withdrawToken(bytes32 salt, uint256 fnftId, uint256 quantity, address destination) internal {
        // If the FNFT is an old one, this just assigns to zero-value
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        uint256 amountToWithdraw;

        //When the user deposits Eth it stores the asset as address(0xdead) but actual WETH is kept in the vault
        address transferAsset = fnft.asset == address(0xdead) ? WETH : fnft.asset;

        address smartWalletAddr = getAddressForFNFT(salt);

        uint256 supplyBefore = IFNFTHandler(fnft.handler).totalSupply(fnftId) + quantity;

        amountToWithdraw = quantity.mulDivDown(supplyBefore * fnft.depositAmount, supplyBefore);

        // Deploy the smart wallet object
        tokenVault.withdrawToken(salt, transferAsset, amountToWithdraw, address(this));

        //Return ETH to the user or WETH
        if (fnft.asset == address(0xdead)) {
            IWETH(WETH).withdraw(amountToWithdraw);
            destination.safeTransferETH(amountToWithdraw);
        } else {
            ERC20(fnft.asset).safeTransfer(destination, amountToWithdraw);
        }

        emit WithdrawERC20(transferAsset, destination, fnftId, amountToWithdraw, smartWalletAddr);

        emit RedeemFNFT(salt, fnftId, destination);
    }

    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
        external
        returns (bytes[] memory)
    {
        /*
        * You inherit the actual proxyCall implementation from the revest_base and then only need to override
        * the functionality to determine if the user is allowed to call the function on the FNFT
        */

        IRevest.FNFTConfig memory fnft = fnfts[salt];

        IFNFTHandler FNFTHandler = IFNFTHandler(fnft.handler);

        //You Must own the entire supply to call a function on the FNFT
        uint256 supply = FNFTHandler.totalSupply(fnft.fnftId);
        require(supply != 0 && FNFTHandler.balanceOf(msg.sender, fnft.fnftId) == supply, "E007");

        return _proxyCall(salt, targets, values, calldatas, fnft.lockManager, fnft.asset);
    }

    function getAddressForFNFT(bytes32 salt) public view virtual returns (address smartWallet) {
        smartWallet = tokenVault.getAddress(salt, address(this));
    }

    function fnftIdToRevestId(address handler, uint256 fnftId) public pure returns (bytes32 salt) {
        salt = keccak256(abi.encode(fnftId, handler, 0));
    }
}
