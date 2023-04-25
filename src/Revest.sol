// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@solmate/utils/SafeTransferLib.sol";


import "./interfaces/IRevest.sol";
import "./interfaces/IAddressRegistry.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/IOutputReceiver.sol";
import "./interfaces/IAddressLock.sol";

import "./utils/RevestAccessControl.sol";

import "./lib/IWETH.sol";

/**
 * This is the entrypoint for the frontend, as well as third-party Revest integrations.
 * Solidity style guide ordering: receive, fallback, external, public, internal, private - within a grouping, view and pure go last - https://docs.soliditylang.org/en/latest/style-guide.html
 */
contract Revest is IRevest, RevestAccessControl, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ERC165Checker for address;

    bytes4 public constant ADDRESS_LOCK_INTERFACE_ID = type(IAddressLock).interfaceId;
    bytes4 public constant OUTPUT_RECEIVER_INTERFACE_ID = type(IOutputReceiver).interfaceId;

    address immutable WETH;

    /// Point at which FNFTs should point to the new token vault

    uint public erc20Fee; // out of 1000
    uint public constant erc20multiplierPrecision = 1000;
    uint public flatWeiFee;
    uint public constant MAX_INT = 2**256 - 1;

    mapping(address => bool) public approved;
    mapping(address => bool) public whitelisted;
    mapping(bytes32 => IRevest.FNFTConfig) public fnfts;
    mapping(address handler => mapping(uint nftId => uint numfnfts)) public numfnfts;
    
    /**
     * @dev Primary constructor to create the Revest controller contract
     */
    constructor(
        address provider,
        address weth
    ) RevestAccessControl(provider) {
        WETH = weth;
    }

    // PUBLIC FUNCTIONS

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
        IRevest.FNFTConfig memory fnftConfig
    ) external payable override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        IFNFTHandler fnftHandler = getFNFTHandler();

        uint fnftNum;

        //If the handler is the Revest FNFT Contract get the new FNFT ID
        if (handler == address(fnftHandler)) {
            fnftId = fnftHandler.getNextId();
        }

        else {
            //Each NFT for a handler as an identifier, so that you can mint multiple fnfts to the same nft
            fnftNum = numfnfts[handler][fnftId]++;
        }

        /*
        * The hash will always be unique and non-overwritable
        * If you mint to the revest handler then fnftId will be an incrementing number
        * If you mint to any other handler, then the numfnfts mapping will be incremented everytime
        * This allows you to mint multiple fnfts to the same nft with different identifiers
        */
        salt = keccak256(abi.encode(fnftId, handler, fnftNum));
        require(fnfts[salt].depositAmount == 0, "E007");//TODO: Double check that Error #
       
        // Get or create lock based on time, assign lock to ID
        {
            IRevest.LockParam memory timeLock;
            timeLock.lockType = IRevest.LockType.TimeLock;
            timeLock.timeLockExpiry = endTime;
            lockId = getLockManager().createLock(salt, timeLock);
        }

        doMint(recipients, quantities, fnftId, handler, fnftNum, fnftConfig, msg.value);

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
        IRevest.FNFTConfig memory fnftConfig
    ) external payable override nonReentrant returns (bytes32 salt, bytes32 lockId) {
        IFNFTHandler fnftHandler = getFNFTHandler();

        uint fnftNum;

        //If the handler is the Revest FNFT Contract get the new FNFT ID
        if (handler == address(fnftHandler)) {
            fnftId = fnftHandler.getNextId();
        }

        else {
            //Each NFT for a handler as an identifier, so that you can mint multiple fnfts to the same nft
            fnftNum = numfnfts[handler][fnftId]++;
        }

        /*
        * The hash will always be unique and non-overwritable
        * If you mint to the revest handler then fnftId will be an incrementing number
        * If you mint to any other handler, then the numfnfts mapping will be incremented everytime
        * This allows you to mint multiple fnfts to the same nft with different identifiers
        */
        salt = keccak256(abi.encode(fnftId, handler, fnftNum));
        require(fnfts[salt].depositAmount == 0, "E007");//TODO: Double check that Error code

        {
            IRevest.LockParam memory addressLock;
            addressLock.addressLock = trigger;
            addressLock.lockType = IRevest.LockType.AddressLock;

            //Return the ID of the lock
            lockId = getLockManager().createLock(salt, addressLock);

            // The lock ID is already incremented prior to calling a method that could allow for reentry
            if(trigger.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)) {
                IAddressLock(trigger).createLock(fnftId, uint(lockId), arguments);
            }
        }

        doMint(recipients, quantities, fnftId, handler, fnftNum, fnftConfig, msg.value);

        emit FNFTAddressLockMinted(fnftConfig.asset, _msgSender(), fnftId, trigger, quantities, fnftConfig);

    }

    function withdrawFNFT(uint fnftId, address handler, uint fnftNum, uint quantity) external override nonReentrant {
        bytes32 salt = keccak256(abi.encode(fnftId, handler, fnftNum));

        address asset = fnfts[salt].asset;
        _withdrawFNFT(fnftId, handler, fnftNum, asset, quantity);
    }

    /// Advanced FNFT withdrawals removed for the time being – no active implementations
    /// Represents slightly increased surface area – may be utilized in Resolve

    function unlockFNFT(address handler, uint fnftId, uint fnftNum) external override nonReentrant  {
        bytes32 salt = keccak256(abi.encode(fnftId, handler, fnftNum));

        // Works for value locks or time locks
        IRevest.LockType lock = getLockManager().lockTypes(salt);
        require(lock == IRevest.LockType.AddressLock, "E008");
        require(getLockManager().unlockFNFT(salt, fnftId, _msgSender()), "E056");

        //TODO: Fix Events
        emit FNFTUnlocked(_msgSender(), fnftId);
    }

   //TODO: I just removed Splitting cause we never re-enabled it

    /// @return the FNFT ID
    function extendFNFTMaturity(
        uint fnftId,
        address handler,
        uint fnftNum,
        uint endTime
    ) external override nonReentrant returns (uint) {
        bytes32 salt = keccak256(abi.encode(fnftId, handler, fnftNum));

        IFNFTHandler fnftHandler = getFNFTHandler();
        uint supply = fnftHandler.getSupply(fnftId);
        uint balance = fnftHandler.getBalance(_msgSender(), fnftId);

        require(endTime > block.timestamp, 'E002');
        require(fnftId < fnftHandler.getNextId(), "E007");
        require(balance == supply , "E022");

        IRevest.FNFTConfig memory config = getFNFT(salt);
        ILockManager manager = getLockManager();
        // If it can't have its maturity extended, revert
        // Will also return false on non-time lock locks
        require(config.maturityExtension &&
            manager.lockTypes(salt) == IRevest.LockType.TimeLock, "E029");
        // If desired maturity is below existing date, reject operation
        require(manager.getLock(salt).timeLockExpiry < endTime, "E030");

        // Update the lock
        IRevest.LockParam memory lock;
        lock.lockType = IRevest.LockType.TimeLock;
        lock.timeLockExpiry = endTime;

        manager.createLock(salt, lock);

        // Callback to IOutputReceiverV3
        // NB: All IOuputReceiver systems should be either marked non-reentrant or ensure they follow checks-effects-interactions
        if(config.pipeToContract != address(0) && config.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(config.pipeToContract).handleTimelockExtensions(fnftId, endTime, _msgSender());
        }

        emit FNFTMaturityExtended(_msgSender(), fnftId, endTime);

        return fnftId;
    }

    /**
     * Amount will be per FNFT. So total ERC20s needed is amount * quantity.
     * We don't charge an ETH fee on depositAdditional, but do take the erc20 percentage.
     */
    function depositAdditionalToFNFT(
        uint fnftId,
        address handler,
        uint fnftNum,
        uint amount,
        uint quantity
    ) external override nonReentrant returns (uint) {
        bytes32 salt = keccak256(abi.encode(fnftId, handler, fnftNum));

        address vault = addressesProvider.getTokenVault();
        IRevest.FNFTConfig memory fnft = getFNFT(salt);

        require(fnftId < IFNFTHandler(handler).getNextId(), "E007");
        require(fnft.isMulti, "E034");
        require(fnft.depositStopTime > block.timestamp || fnft.depositStopTime == 0, "E035");
        require(quantity > 0, "E070");
        // This line will disable all legacy FNFTs from using this function
        // Unless they are using it for pass-through
        require(fnft.depositMul == 0 || fnft.asset == address(0), 'E084');

        uint supply = IFNFTHandler(handler).getSupply(fnftId);
        uint deposit = quantity * amount;

        // Future versions may reintroduce series splitting, if it is ever in demand
        require(quantity == supply, 'E083');

        // Transfer the ERC20 fee to the admin address, leave it at that
        if(!whitelisted[_msgSender()]) {
            uint totalERC20Fee = erc20Fee * deposit / erc20multiplierPrecision;
            if(totalERC20Fee > 0) {
                // NB: The user has control of where this external call goes (fnft.asset)
                ERC20(fnft.asset).safeTransferFrom(_msgSender(), addressesProvider.getAdmin(), totalERC20Fee);
            }
        }


        // Transfer to the smart wallet
        if(fnft.asset != address(0)){
            address smartWallet = ITokenVault(vault).getFNFTAddress(salt);
            // NB: The user has control of where this external call goes (fnft.asset)
            ERC20(fnft.asset).safeTransferFrom(_msgSender(), smartWallet, deposit);

            emit DepositERC20(fnfts[salt].asset, _msgSender(), fnftId, quantity, smartWallet);

        }
                       
        if(fnft.pipeToContract != address(0) && fnft.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) {
            IOutputReceiver(fnft.pipeToContract).handleAdditionalDeposit(fnftId, amount, quantity, _msgSender());
        }

        emit FNFTAddionalDeposited(_msgSender(), fnftId, quantity, amount);

        return 0;
    }

    //
    // INTERNAL FUNCTIONS
    //

    // Private function for use in withdrawing FNFTs, allow us to make universal use of reentrancy guard 
    function _withdrawFNFT(uint fnftId, address handler, uint fnftNum, address _token, uint quantity) private {
        bytes32 salt = keccak256(abi.encode(fnftId, handler, fnftNum));

        // Check if this many FNFTs exist in the first place for the given ID
        require(quantity > 0, "E003");

        // Burn the FNFTs being exchanged
        if (handler == address(getFNFTHandler())) {
            IFNFTHandler(handler).burn(_msgSender(), fnftId, quantity);
        }

        require(getLockManager().unlockFNFT(salt, fnftId, _msgSender()), 'E082');

        //TODO: State Cleanup

        address vault = addressesProvider.getTokenVault();

        ITokenVault(vault).withdrawToken(salt, _token, quantity, _msgSender());

        emit FNFTWithdrawn(_msgSender(), fnftId, quantity);
    }

    function doMint(
        address[] memory recipients,
        uint[] memory quantities,
        uint fnftId,
        address handler,
        uint fnftNum,
        IRevest.FNFTConfig memory fnftConfig,
        uint weiValue
    ) internal {
        bytes32 salt = keccak256(abi.encode(fnftId, handler, fnftNum));

        bool isSingular;
        uint totalQuantity = quantities[0];
        {
            uint rec = recipients.length;
            uint quant = quantities.length;
            require(rec == quant, "recipients and quantities arrays must match");
            // Calculate total quantity
            isSingular = rec == 1;
            if(!isSingular) {
                for(uint i = 1; i < quant; i++) {
                    totalQuantity += quantities[i];
                }
            }
            require(totalQuantity > 0, "E003");
        }

        // Gas optimization
        // Will always be new token vault
        address vault = addressesProvider.getTokenVault();

        // Take fees
        if(weiValue > 0) {
            // Immediately convert all ETH to WETH
            IWETH(WETH).deposit{value: weiValue}();
        }

        // For multi-chain deployments, will relay through RewardsHandlerSimplified to end up in admin wallet
        // Whitelist system will charge fees on all but approved parties, who may charge them using negotiated
        // values with the Revest Protocol
        if(!whitelisted[_msgSender()]) {
            if(flatWeiFee > 0) {
                require(weiValue >= flatWeiFee, "E005");
                address reward = addressesProvider.getRewardsHandler();
                if(!approved[reward]) {
                    IERC20(WETH).approve(reward, MAX_INT);
                    approved[reward] = true;
                }
                IRewardsHandler(reward).receiveFee(WETH, flatWeiFee);
            }
            
            // If we aren't depositing any value, no point running this
            if(fnftConfig.depositAmount > 0) {
                uint totalERC20Fee = erc20Fee * totalQuantity * fnftConfig.depositAmount / erc20multiplierPrecision;
                if(totalERC20Fee > 0) {
                    // NB: The user has control of where this external call goes (fnftConfig.asset)
                    ERC20(fnftConfig.asset).safeTransferFrom(_msgSender(), addressesProvider.getAdmin(), totalERC20Fee);
                }
            }

            // If there's any leftover ETH after the flat fee, convert it to WETH
            weiValue -= flatWeiFee;
        }
        
        // Convert ETH to WETH if necessary
        if(weiValue > 0) {
            // If the asset is WETH, we also enable sending ETH to pay for the tx fee. Not required though
            require(fnftConfig.asset == WETH, "E053");
            require(weiValue >= fnftConfig.depositAmount, "E015");
        }
        
        
        // Create the FNFT and update accounting within TokenVault
        createFNFT(salt, fnftId, handler, fnftNum, fnftConfig, totalQuantity);

        // Now, we move the funds to token vault from the message sender
        if(fnftConfig.asset != address(0)){
            address smartWallet = ITokenVault(vault).getFNFTAddress(salt);
            // NB: The user has control of where this external call goes (fnftConfig.asset)
            ERC20(fnftConfig.asset).safeTransferFrom(_msgSender(), smartWallet, totalQuantity * fnftConfig.depositAmount);
        }

        //Mint FNFTs but only if the handler is the Revest FNFT Handler
        if (handler == address(getFNFTHandler())) {
            if(isSingular) {
                getFNFTHandler().mint(recipients[0], fnftId, quantities[0], '');
            } else {
                getFNFTHandler().mintBatchRec(recipients, quantities, fnftId, totalQuantity, '');
            }
        }

    }

    function createFNFT(bytes32 salt,
            uint fnftId, 
            address handler, 
            uint fnftNum,
            IRevest.FNFTConfig memory fnftConfig, 
            uint quantity
            ) internal {
            
            fnfts[salt].asset =  fnftConfig.asset;
            fnfts[salt].depositAmount =  fnftConfig.depositAmount;
            fnfts[salt].fnftNum = fnftNum;
            fnfts[salt].fnftId = fnftId;
            fnfts[salt].handler = handler;
            fnfts[salt].quantity = quantity;


            if(fnftConfig.depositMul != 0) {
                fnfts[salt].depositMul = fnftConfig.depositMul;
            }
            
            if(fnftConfig.split != 0) {
                fnfts[salt].split = fnftConfig.split;
            }

            if(fnftConfig.maturityExtension) {
                fnfts[salt].maturityExtension = fnftConfig.maturityExtension;
            }

            if(fnftConfig.pipeToContract != address(0)) {
                fnfts[salt].pipeToContract = fnftConfig.pipeToContract;
            }

            if(fnftConfig.isMulti) {
                fnfts[salt].isMulti = fnftConfig.isMulti;
                fnfts[salt].depositStopTime = fnftConfig.depositStopTime;
            }

            if(fnftConfig.nontransferrable){
                fnfts[salt].nontransferrable = fnftConfig.nontransferrable;
            }

        }//createFNFT


    function getFNFT(bytes32 fnftId) public view returns (IRevest.FNFTConfig memory) {
        return fnfts[fnftId];
    }

    function setFlatWeiFee(uint wethFee) external override onlyOwner {
        flatWeiFee = wethFee;
    }

    function setERC20Fee(uint erc20) external override onlyOwner {
        erc20Fee = erc20;
    }

    function getFlatWeiFee() external view override returns (uint) {
        return flatWeiFee;
    }

    function getERC20Fee() external view override returns (uint) {
        return erc20Fee;
    }

    /**
     * @dev Returns the cached IAddressRegistry connected to this contract
     **/
    function getAddressesProvider() external view returns (IAddressRegistry) {
        return addressesProvider;
    }

    /// Used to whitelist a contract for custom fee behavior
    function modifyWhitelist(address contra, bool listed) external onlyOwner {
        whitelisted[contra] = listed;
    }

}
