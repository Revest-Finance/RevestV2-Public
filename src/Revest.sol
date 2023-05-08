// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

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
import "./interfaces/IOutputReceiver.sol";
import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IAddressLock.sol";
import "./interfaces/IAllowanceTransfer.sol";
import "./interfaces/IRewardsHandler.sol";

import "./lib/IWETH.sol";

/**
 * This is the entrypoint for the frontend, as well as third-party Revest integrations.
 * Solidity style guide ordering: receive, fallback, external, public, internal, private - within a grouping, view and pure go last - https://docs.soliditylang.org/en/latest/style-guide.html
 */
contract Revest is IRevest, ReentrancyGuard, Ownable {
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
    address immutable FEE_RECIPIENT;
    IRewardsHandler rewardsHandler;

    //Deployed omni-chain to same address
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint public fee; // out of 1e18
    uint public constant BASIS_POINTS = 1 ether;

    mapping(bytes32 => IRevest.FNFTConfig) public fnfts;
    mapping(address handler => mapping(uint nftId => uint numfnfts)) public numfnfts;
    mapping(bytes4 selector => bool blackListed) public blacklistedFunctions;
     
    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(
        address weth,
        address _tokenVault,
        address _FEE_RECIPIENT,
        address _rewardsHandler
    ) Ownable() {
        WETH = weth;
        tokenVault = ITokenVault(_tokenVault); 
        FEE_RECIPIENT = _FEE_RECIPIENT;
        rewardsHandler = IRewardsHandler(_rewardsHandler);
    }

    function setPermitAllowance(IAllowanceTransfer.PermitBatch calldata _permit, bytes calldata _signature) internal {
        PERMIT2.permit(_msgSender(), _permit, _signature);
    }

    /**
     * @dev creates a single time-locked NFT with <quantity> number of copies with <amount> of <asset> stored for each copy
     * asset - the address of the underlying ERC20 token for this bond
     * amount - the amount to store per NFT if multiple NFTs of this variety are being created
     * unlockTime - the timestamp at which this will unlock
     * quantity – the number of FNFTs to create with this operation     
     */
    function mintTimeLock(
        address handler, 
        uint fnftId,
        uint endTime,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        if (_signature.length != 0) setPermitAllowance(permits, _signature);

        uint nonce;

        //If the handler is the Revest FNFT Contract get the new FNFT ID
        if (handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            fnftId = IFNFTHandler(handler).getNextId();
        }

        else if (handler.supportsInterface(ERC721_INTERFACE_ID)) {
            //Each NFT for a handler as an identifier, so that you can mint multiple fnfts to the same nft
            nonce = numfnfts[handler][fnftId]++;
        }

        else {
            revert("E001");
        }

        // Get or create lock based on time, assign lock to ID
        {   
            salt = keccak256(abi.encode(fnftId, handler, nonce));
            require(fnfts[salt].quantity == 0, "E007");//TODO: Double check that Error #

            IRevest.LockParam memory timeLock;
            timeLock.lockType = IRevest.LockType.TimeLock;
            timeLock.timeLockExpiry = endTime;
            lockId = ILockManager(fnftConfig.lockManager).createLock(salt, timeLock);
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(
            handler,
            fnftId,
            nonce,
            endTime,
            recipients,
            quantities,
            fnftConfig,
            _signature.length == 0
        ));

        //TODO: Fix Events
        emit FNFTTimeLockMinted(fnftConfig.asset, _msgSender(), fnftId, endTime, quantities, fnftConfig);

    }

    function mintAddressLock(
        address handler,
        uint fnftId,
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        if (_signature.length != 0) setPermitAllowance(permits, _signature);

        uint nonce;
        //If the handler is the Revest FNFT Contract get the new FNFT ID
        if (handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            fnftId = IFNFTHandler(handler).getNextId();
        }

        else if (handler.supportsInterface(ERC721_INTERFACE_ID)) {
            //Each NFT for a handler as an identifier, so that you can mint multiple fnfts to the same nft
            nonce = numfnfts[handler][fnftId]++;
        }

        else {
            revert("E001");
        }
       
        {
            salt = keccak256(abi.encode(fnftId, handler, nonce));
            require(fnfts[salt].quantity == 0, "E007");//TODO: Double check that Error code

            IRevest.LockParam memory addressLock;
            addressLock.addressLock = trigger;
            addressLock.lockType = IRevest.LockType.AddressLock;

            //Return the ID of the lock
            lockId = ILockManager(fnftConfig.lockManager).createLock(salt, addressLock);

            // The lock ID is already incremented prior to calling a method that could allow for reentry
            if(trigger.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)) {
                IAddressLock(trigger).createLock(fnftId, uint(lockId), arguments);
            }
        }

        //Stack Too Deep Fixer
        doMint(MintParameters(
            handler,
            fnftId,
            nonce,
            0,
            recipients,
            quantities,
            fnftConfig,
            _signature.length == 0
        ));

        emit FNFTAddressLockMinted(fnftConfig.asset, _msgSender(), fnftId, trigger, quantities, fnftConfig);
    }

    function withdrawFNFT(bytes32 salt) external override nonReentrant {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Check if this many FNFTs exist in the first place for the given ID
        require(fnft.quantity > 0, "E003");

        // Burn the FNFTs being exchanged
        if (fnft.handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            IFNFTHandler(fnft.handler).burn(_msgSender(), fnft.fnftId, fnft.quantity);
        }

        //Checks-effects because unlockFNFT has an external call which could be used for reentrancy
        fnfts[salt].quantity -= fnft.quantity;

        require(ILockManager(fnft.lockManager).unlockFNFT(salt, fnft.fnftId, _msgSender()), 'E082');

        withdrawToken(salt, fnft.fnftId, fnft.quantity, _msgSender());

        emit FNFTWithdrawn(_msgSender(), fnft.fnftId, fnft.quantity);
    }

    /// Advanced FNFT withdrawals removed for the time being – no active implementations
    /// Represents slightly increased surface area – may be utilized in Resolve

    function unlockFNFT(bytes32 salt) external override nonReentrant  {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        // Works for value locks or time locks
        IRevest.LockType lock = ILockManager(fnft.lockManager).lockTypes(salt);
        require(lock == IRevest.LockType.AddressLock, "E008");
        require(ILockManager(fnft.lockManager).unlockFNFT(salt, fnft.fnftId, _msgSender()), "E056");

        //TODO: Fix Events
        emit FNFTUnlocked(_msgSender(), fnft.fnftId);
    }

   //TODO: I just removed Splitting cause we never re-enabled it

    /// @return the FNFT ID
    function extendFNFTMaturity(
        bytes32 salt,
        uint endTime
    ) external override nonReentrant returns (uint) {
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        uint fnftId = fnft.fnftId;
        address handler = fnft.handler;

        //Require that the FNFT exists
        require(fnft.quantity != 0); 

        require(endTime > block.timestamp, 'E002');

        if (handler.supportsInterface(ERC721_INTERFACE_ID)) {
            //Only the NFT owner can extend the lock on the NFT
            require(IERC721(handler).ownerOf(fnftId) == msg.sender);
        }

        else if (handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            IFNFTHandler fnftHandler = IFNFTHandler(handler);

            require(fnftId < fnftHandler.getNextId(), "E007");

            require(fnftId < IFNFTHandler(handler).getNextId(), "E007");
            uint supply = fnftHandler.totalSupply(fnftId);

            uint balance = fnftHandler.getBalance(_msgSender(), fnftId);

            //To extend the maturity you must own the entire supply so you can't extend someone eles's lock time
            require(supply != 0 && balance == supply , "E022");
        }

        else {
            revert("E001");
        }

        ILockManager manager = ILockManager(fnft.lockManager);
        
        // If it can't have its maturity extended, revert
        // Will also return false on non-time lock locks
        require(fnft.maturityExtension &&
            manager.lockTypes(salt) == IRevest.LockType.TimeLock, "E029");

        // If desired maturity is below existing date, reject operation
        require(manager.getLock(salt).timeLockExpiry < endTime, "E030");

        // Update the lock
        IRevest.LockParam memory lock;
        lock.lockType = IRevest.LockType.TimeLock;
        lock.timeLockExpiry = endTime;

        manager.createLock(salt, lock);

        // Callback to IOutputReceiverV3
        if(fnft.pipeToContract != address(0) && fnft.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(fnft.pipeToContract).handleTimelockExtensions(fnftId, endTime, _msgSender());
        }

        emit FNFTMaturityExtended(_msgSender(), fnftId, endTime);

        return fnftId;
    }

    /**
     * Amount will be per FNFT. So total ERC20s needed is amount * quantity.
     * We don't charge an ETH fee on depositAdditional, but do take the erc20 percentage.
     */
    function depositAdditionalToFNFT(
        bytes32 salt,
        uint amount,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external override nonReentrant returns (uint deposit) {
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        uint fnftId = fnft.fnftId;
        address handler = fnft.handler;

        if (_signature.length != 0) setPermitAllowance(permits, _signature);

        require(fnft.quantity != 0);

        if (handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            require(fnftId < IFNFTHandler(handler).getNextId(), "E007");
        }

        //If the handler is an NFT then supply is 1
        uint supply = 1;
        if (handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            supply = IFNFTHandler(handler).totalSupply(fnftId);
        }

        // Transfer the ERC20 fee to the admin address, leave it at that
        address smartWallet = tokenVault.getFNFTAddress(salt, address(this));

        deposit = supply * amount;
       
        // Transfer to the smart wallet
        if(fnft.asset != address(0) && amount != 0) {
            if (_signature.length != 0) {
                PERMIT2.transferFrom(_msgSender(), smartWallet, deposit.toUint160(), fnft.asset);
            }

            else {
                ERC20(fnft.asset).safeTransferFrom(_msgSender(), smartWallet, deposit);
            }

            emit DepositERC20(fnft.asset, _msgSender(), fnftId, amount, smartWallet);

            if(fee != 0) {
                //TODO: Fee Taking
                uint totalERC20Fee = fee.mulDivDown(deposit, BASIS_POINTS);
                if(totalERC20Fee != 0) {
                    if (_signature.length != 0) {
                        PERMIT2.transferFrom(_msgSender(), FEE_RECIPIENT, totalERC20Fee.toUint160(), fnft.asset);
                    }
                    else {
                        ERC20(fnft.asset).safeTransferFrom(_msgSender(), FEE_RECIPIENT, totalERC20Fee);
                    }
                }
            }//if !Whitelisted
        }//if (amount != zero)

        //You don't need to check for address(0) since address(0) does not include support interface        
        if(fnft.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(fnft.pipeToContract).handleAdditionalDeposit(fnftId, deposit, supply, _msgSender());
        }

        emit FNFTAddionalDeposited(_msgSender(), fnftId, supply, amount);
    }

    //
    // INTERNAL FUNCTIONS
    //

    function doMint(
        IRevest.MintParameters memory params
    ) internal {
        bytes32 salt = keccak256(abi.encode(params.fnftId, params.handler, params.nonce));

        bool isSingular;
        uint totalQuantity = params.quantities[0];
        {
            require(params.recipients.length == params.quantities.length, "recipients and quantities arrays must match");
            // Calculate total quantity
            isSingular = params.recipients.length == 1;
            if(!isSingular) {
                for(uint i = 1; i < params.quantities.length; i++) {
                    totalQuantity += params.quantities[i];
                }
            }
            require(totalQuantity > 0, "E003");
        }

        // Take fees
        if (msg.value != 0) {
            params.fnftConfig.asset = address(0);
            params.fnftConfig.depositAmount = msg.value;
            params.fnftConfig.useETH = true;
            IWETH(WETH).deposit{value: msg.value}();
        }

        takeFees(params.fnftConfig, totalQuantity, params.usePermit2);
        
        // Create the FNFT and update accounting within TokenVault
        createFNFT(salt, params.fnftId, params.handler, params.nonce, params.fnftConfig, totalQuantity);

        // Now, we move the funds to token vault from the message sender
        address smartWallet = tokenVault.getFNFTAddress(salt, address(this));
        if (params.usePermit2) {
            PERMIT2.transferFrom(_msgSender(), smartWallet, (totalQuantity * params.fnftConfig.depositAmount).toUint160(), params.fnftConfig.asset);
        }

        else {
            ERC20(params.fnftConfig.asset).safeTransferFrom(_msgSender(), smartWallet, totalQuantity * params.fnftConfig.depositAmount);
        }

        //Mint FNFTs but only if the handler is the Revest FNFT Handler
        if (params.handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            if(isSingular) {
                IFNFTHandler(params.handler).mint(params.recipients[0], params.fnftId, params.quantities[0], '');
            } else {
                IFNFTHandler(params.handler).mintBatchRec(params.recipients, params.quantities, params.fnftId, totalQuantity, '');
            }
        }

        emit CreateFNFT(salt, params.fnftId, _msgSender());
    }

    function takeFees(IRevest.FNFTConfig memory fnftConfig, uint totalQuantity, bool usePermit2) internal {
        if(fee != 0) {
            //TODO: Change Depending on How Fees are Taken in the future
            IRewardsHandler(rewardsHandler).receiveFee(WETH, fee);
            
            uint totalFee = fee.mulDivDown((totalQuantity * fnftConfig.depositAmount), BASIS_POINTS);

            if(totalFee != 0) {
                if (fnftConfig.asset == address(0)) {
                    require(msg.value == (totalQuantity * fnftConfig.depositAmount) + totalFee, "E004");
                    FEE_RECIPIENT.safeTransferETH(totalFee);
                }

                else {
                    if (usePermit2) {
                        PERMIT2.transferFrom(_msgSender(), FEE_RECIPIENT, totalFee.toUint160(), fnftConfig.asset);
                    }

                    else {
                        ERC20(fnftConfig.asset).safeTransferFrom(_msgSender(), FEE_RECIPIENT, totalFee);
                    }
                }


                IRewardsHandler(rewardsHandler).receiveFee(fnftConfig.asset, totalFee);
            }
        }
    }

    function withdrawToken(
        bytes32 salt,
        uint fnftId,
        uint quantity,
        address user
    ) internal {
        // If the FNFT is an old one, this just assigns to zero-value
        IRevest.FNFTConfig memory fnft = fnfts[salt];
        address pipeTo = fnft.pipeToContract;
        uint amountToWithdraw;

        address asset = fnft.asset == address(0) ? WETH : fnft.asset;

        address smartWallAdd = tokenVault.getFNFTAddress(salt, address(this));

        uint supplyBefore = 1;
        if (fnft.handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            supplyBefore = IFNFTHandler(fnft.handler).totalSupply(fnftId) + quantity;
        }

        amountToWithdraw = quantity.mulDivDown(IERC20(asset).balanceOf(smartWallAdd), supplyBefore);

        // Deploy the smart wallet object
        address destination = (pipeTo == address(0)) ? user : pipeTo;
        tokenVault.withdrawToken(salt, asset, amountToWithdraw, address(this));

        if (asset == address(0)) {
            IWETH(WETH).withdraw(amountToWithdraw);
            destination.safeTransferETH(amountToWithdraw);
        }

        else {
            ERC20(asset).safeTransfer(destination, amountToWithdraw);
        }

        emit WithdrawERC20(asset, user, fnftId, amountToWithdraw, smartWallAdd);

        
        if(pipeTo.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(pipeTo).receiveRevestOutput(fnftId, asset, payable(user), quantity);
        }

        emit RedeemFNFT(salt, fnftId, user);
        
    }

    function proxyCall(bytes32 salt, 
                        address[] memory targets, 
                        uint[] memory values, 
                        bytes[] memory calldatas) 
        external returns (bytes[] memory) {
        IRevest.FNFTConfig memory fnft = fnfts[salt];

        if (fnft.handler.supportsInterface(FNFTHANDLER_INTERFACE_ID)) {
            IFNFTHandler FNFTHandler = IFNFTHandler(fnft.handler);

            //You Must own the entire supply to call a function on the FNFT
            uint supply = FNFTHandler.totalSupply(fnft.fnftId);
            require(supply != 0 && FNFTHandler.getBalance(msg.sender, fnft.fnftId) == supply, "E007");
        }

        else if (fnft.handler.supportsInterface(ERC721_INTERFACE_ID)) {
            //Only the NFT owner can call a function on the NFT
            require(IERC721(fnft.handler).ownerOf(fnft.fnftId) == msg.sender);
        }

        else {
            revert("E001");
        }

        for(uint x = 0; x < targets.length; ) {
            require(!blacklistedFunctions[bytes4(calldatas[x])], "E081");

            unchecked {
                ++x;
            }
        }

        return tokenVault.proxyCall(salt, targets, values, calldatas);

    }

    function createFNFT(bytes32 salt,
            uint fnftId, 
            address handler, 
            uint nonce,
            IRevest.FNFTConfig memory fnftConfig, 
            uint quantity
            ) internal {

            fnfts[salt] = fnftConfig;
            
            fnfts[salt].nonce = nonce;
            fnfts[salt].fnftId = fnftId;
            fnfts[salt].handler = handler;
            fnfts[salt].quantity = quantity;

        }//createFNFT

    //You don't need this but it makes it a little easier to return an object and not a bunch of variables
    function getFNFT(bytes32 fnftId) external view returns (IRevest.FNFTConfig memory) {
        return fnfts[fnftId];
    }

    function setFee(uint _fee) external override onlyOwner {
        fee = _fee;
    }

    function changeSelectorVisibility(bytes4 selector, bool designation) external onlyOwner {
        blacklistedFunctions[selector] = designation;
    }

    function transferOwnershipFNFTHandler(address newRevest, address handler) external onlyOwner {
        //Ownership should be a timelocked controller.
        Ownable(handler).transferOwnership(newRevest);
    }

    function modifyRewardsHandler(address newHandler) external onlyOwner {
        rewardsHandler = IRewardsHandler(newHandler);
    }

    receive() external payable {
        //Do Nothing but receive
    }

    fallback() external payable {
        //Do Nothing but receive
    }
}