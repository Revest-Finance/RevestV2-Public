// SPDX-License-Identifier: GNU-GPL v3.0 or later
import "./IAllowanceTransfer.sol";

pragma solidity ^0.8.12;

interface IRevest {
    event FNFTTimeLockMinted(
        address indexed asset,
        address indexed from,
        uint indexed fnftId,
        uint endTime,
        uint[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTAddressLockMinted(
        address indexed asset,
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
        uint mount
    );

    event DepositERC20(
        address indexed token, 
        address indexed user, 
        uint indexed fnftId, 
        uint tokenAmount, 
        address smartWallet
    );

    event WithdrawERC20(
        address indexed token, 
        address indexed user, 
        uint indexed fnftId, 
        uint tokenAmount, 
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
        address asset; // The token being stored
        address lockManager;
        uint depositAmount; // The amount of each token being stored
        uint nonce;// The FNFT number
        uint quantity;// How many FNFTs
        uint fnftId;//the ID of the NFT the FNFT was minted to
        bytes32 lockSalt; // The salt used to generate the lock info
        bool maturityExtension; // Maturity extensions remaining
        bool useETH;
        bool nontransferrable;
    }

    enum LockType {
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
        uint nonce;
        uint endTime;
        address[] recipients;
        uint[] quantities;
        FNFTConfig fnftConfig;
        bool usePermit2;
    }

    function mintTimeLockWithPermit(
        address handler,
        uint fnftId,
        uint endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);

    function mintTimeLock(
        address handler,
        uint fnftId,
        uint endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (bytes32, bytes32);

    function mintAddressLock(
        address handler,
        uint fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (bytes32, bytes32);

    function mintAddressLockWithPermit(
        address handler,
        uint fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);

    function withdrawFNFT(bytes32 salt) external;

    function unlockFNFT(bytes32 salt) external;

    function depositAdditionalToFNFT(
        bytes32 salt,
        uint amount,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external returns (uint);

    function extendFNFTMaturity(
        bytes32 salt,
        uint endTime
    ) external returns (uint);

    function getFNFT(bytes32 salt) external view returns (FNFTConfig memory);

}