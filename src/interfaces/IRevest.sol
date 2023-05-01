// SPDX-License-Identifier: GNU-GPL v3.0 or later
import "./IAllowanceTransfer.sol";

pragma solidity >=0.8.0;

interface IRevest {
    event FNFTTimeLockMinted(
        address[] indexed assets,
        address indexed from,
        uint indexed fnftId,
        uint endTime,
        uint[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTAddressLockMinted(
        address[] indexed assets,
        address indexed from,
        uint indexed fnftId,
        address trigger,
        uint[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTWithdrawn(
        address indexed from,
        uint indexed fnftId,
        uint indexed quantity
    );

    event FNFTSplit(
        address indexed from,
        uint[] indexed newFNFTId,
        uint[] indexed proportions,
        uint quantity
    );

    event FNFTUnlocked(
        address indexed from,
        uint indexed fnftId
    );

    event FNFTMaturityExtended(
        address indexed from,
        uint indexed fnftId,
        uint indexed newExtendedTime
    );

    event FNFTAddionalDeposited(
        address indexed from,
        uint indexed newFNFTId,
        uint indexed quantity,
        uint[] amounts
    );

    event DepositERC20(
        address[] indexed tokens, 
        address indexed user, 
        uint indexed fnftId, 
        uint[] tokenAmounts, 
        address smartWallet
    );

    event WithdrawERC20(
        address[] indexed tokens, 
        address indexed user, 
        uint indexed fnftId, 
        uint[] tokenAmounts, 
        address smartWallet
    );

    event CreateFNFT(
        bytes32 salt,
        uint indexed fnftId, 
        address indexed from
    );
    
    event RedeemFNFT(
        bytes32 indexed salt,
        uint indexed fnftId, 
        address indexed from
    );


    struct FNFTConfig {
        address pipeToContract; // Indicates if FNFT will pipe to another contract
        address handler;
        address[] assets; // The token being stored
        uint[] assetAmounts; // The amount of each token being stored
        uint fnftNum;// The FNFT number
        uint depositMul; // Deposit multiplier
        uint split; // Number of splits remaining
        uint depositStopTime;//
        uint quantity;// How many FNFTs
        uint fnftId;//the ID of the NFT the FNFT was minted to
        bool maturityExtension; // Maturity extensions remaining
        bool isMulti; //
        bool nontransferrable; // False by default (transferrable) //
    }

    // Refers to the global balance for an ERC20, encompassing possibly many FNFTs
    struct TokenTracker {
        uint lastBalance;
        uint lastMul;
    }

    enum LockType {
        DoesNotExist,
        TimeLock,
        AddressLock
    }

    struct LockParam {
        address addressLock;
        uint timeLockExpiry;
        LockType lockType;
    }

    struct Lock {
        address addressLock;
        LockType lockType;
        uint timeLockExpiry;
        uint creationTime;
        bool unlocked;
    }

    struct MintParameters {
        address handler;
        uint fnftId;
        uint fnftNum;
        uint endTime;
        address[] recipients;
        uint[] quantities;
        FNFTConfig fnftConfig;
    }


    function mintTimeLock(
        address handler,
        uint fnftId,
        uint endTime,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);


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
    ) external payable returns (bytes32, bytes32);

    function withdrawFNFT(uint fnftId, address handler, uint fnftNum, uint quantity) external;

    function unlockFNFT(address handler, uint fnftId, uint fnftNum) external;

    function depositAdditionalToFNFT(
        uint fnftId,
        address handler,
        uint fnftNum,
        uint[] memory amounts,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external returns (uint);

    function extendFNFTMaturity(
        uint fnftId,
        address handler,
        uint fnftNum,
        uint endTime
    ) external returns (uint);

    function setFlatWeiFee(uint wethFee) external;

    function setERC20Fee(uint erc20) external;

    function getFlatWeiFee() external view returns (uint);

    function getERC20Fee() external view returns (uint);

    function getFNFT(bytes32 salt) external view returns (FNFTConfig memory);


}
