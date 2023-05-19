// SPDX-License-Identifier: GNU-GPL v3.0 or later
import "./IAllowanceTransfer.sol";

pragma solidity ^0.8.12;

interface IRevest {
    event FNFTTimeLockMinted(
        address indexed asset,
        address indexed from,
        uint256 indexed fnftId,
        uint256 endTime,
        uint256[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTAddressLockMinted(
        address indexed asset,
        address indexed from,
        uint256 indexed fnftId,
        address trigger,
        uint256[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTWithdrawn(address indexed from, uint256 indexed fnftId, uint256 indexed quantity);

    event FNFTUnlocked(address indexed from, uint256 indexed fnftId);

    event FNFTMaturityExtended(
        bytes32 indexed newLockId, address from, uint256 indexed fnftId, uint256 indexed newExtendedTime
    );

    event FNFTAddionalDeposited(
        address indexed from, uint256 indexed newFNFTId, uint256 indexed quantity, uint256 mount
    );

    event DepositERC20(
        address indexed token, address indexed user, uint256 indexed fnftId, uint256 tokenAmount, address smartWallet
    );

    event WithdrawERC20(
        address indexed token, address indexed user, uint256 indexed fnftId, uint256 tokenAmount, address smartWallet
    );

    event CreateFNFT(bytes32 salt, uint256 indexed fnftId, address indexed from);

    event RedeemFNFT(bytes32 indexed salt, uint256 indexed fnftId, address indexed from);

    struct FNFTConfig {
        address pipeToContract; // Indicates if FNFT will pipe to another contract
        address handler;
        address asset; // The token being stored
        address lockManager;
        uint256 depositAmount; // The amount of each token being stored
        uint256 nonce; // The FNFT number
        uint256 quantity; // How many FNFTs
        uint256 fnftId; //the ID of the NFT the FNFT was minted to
        bytes32 lockId; // The salt used to generate the lock info
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
        uint256 timeLockExpiry;
        LockType lockType;
    }

    struct Lock {
        address addressLock;
        address creator;
        LockType lockType;
        uint256 timeLockExpiry;
        uint256 creationTime;
        bool unlocked;
    }

    struct MintParameters {
        uint256 fnftId;
        uint256 nonce;
        uint256 endTime;
        address[] recipients;
        uint256[] quantities;
        FNFTConfig fnftConfig;
        bool usePermit2;
    }

    function mintTimeLockWithPermit(
        uint256 fnftId,
        uint256 endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);

    function mintTimeLock(
        uint256 fnftId,
        uint256 endTime,
        bytes32 lockSalt,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (bytes32, bytes32);

    function mintAddressLock(
        uint256 fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (bytes32, bytes32);

    function mintAddressLockWithPermit(
        uint256 fnftId,
        address trigger,
        bytes32 lockSalt,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);

    function withdrawFNFT(bytes32 salt, uint256 quantity) external;

    function unlockFNFT(bytes32 salt) external;

    function depositAdditionalToFNFTWithPermit(
        bytes32 salt,
        uint256 amount,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external returns (uint256);

    function depositAdditionalToFNFT(bytes32 salt, uint256 amount) external returns (uint256);

    function extendFNFTMaturity(bytes32 salt, uint256 endTime) external returns (bytes32);

    function getFNFT(bytes32 salt) external view returns (FNFTConfig memory);

    //They're public variables in Revest_base but its useful to define it in the interface also
    function numfnfts(address, uint256) external view returns (uint256);
    function blacklistedFunctions(bytes4) external view returns (bool);
}
