// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/IAddressLock.sol";
import "./lib/IWETH.sol";

import "forge-std/console.sol";

contract LockManager is ILockManager, ReentrancyGuard {
    using ERC165Checker for address;

    bytes4 public constant ADDRESS_LOCK_INTERFACE_ID = type(IAddressLock).interfaceId;
    mapping(bytes32 => ILockManager.Lock) public locks; // maps lockId to locks

    mapping(bytes4 selector => bool) public blacklistedSelector;

    address public immutable WETH;

    constructor(address _WETH) {
        blacklistedSelector[IERC20.transfer.selector] = true;
        blacklistedSelector[IERC20.approve.selector] = true;
        blacklistedSelector[IERC20.transferFrom.selector] = true;
        WETH = _WETH;
    }

    function getLock(bytes32 salt) external view override returns (ILockManager.Lock memory) {
        return locks[salt];
    }

    function createLock(bytes32 salt, ILockManager.LockParam memory lock)
        external
        override
        nonReentrant
        returns (bytes32 lockId)
    {
        lockId = keccak256(abi.encode(salt, msg.sender));
        console.log("---generated lockId--");
        console.logBytes32(lockId);

        // Extensive validation on creation
        ILockManager.Lock memory newLock;

        newLock.lockType = lock.lockType;
        newLock.creationTime = block.timestamp;
        newLock.creator = msg.sender;
        console.log("timestamp: ", block.timestamp);


        if (lock.lockType == ILockManager.LockType.TimeLock) {
            require(lock.timeLockExpiry > block.timestamp, "E015");
            newLock.timeLockExpiry = lock.timeLockExpiry;
        } else if (lock.lockType == ILockManager.LockType.AddressLock) {
            require(lock.addressLock != address(0), "E016");
            newLock.addressLock = lock.addressLock;
        } else {
            revert("E017");
        }

        //Use a single SSTORE
        locks[lockId] = newLock;
    }

    /**
     * @dev Sets the maturity of an address or value lock to mature – can only be called from main contract
     * if address, only if it is called by the address given permissions to
     * if value, only if value is correct for unlocking
     * lockId - the ID of the FNFT to unlock
     */
    function unlockFNFT(bytes32 lockId, uint256 fnftId) external override nonReentrant {
        //Allows reduction to 1 SSTORE at the end as opposed to many
        ILockManager.Lock memory tempLock = locks[lockId];

        require(tempLock.creationTime != 0, "LOCK DOES NOT EXIST");

        //If already unlocked, no state changes needed
        if (tempLock.unlocked) return;

        if (tempLock.lockType == ILockManager.LockType.TimeLock) {
            require(tempLock.timeLockExpiry <= block.timestamp, "E006");
            tempLock.timeLockExpiry = 0;
        } else if (tempLock.lockType == ILockManager.LockType.AddressLock) {
            require(
                tempLock.addressLock.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)
                    && IAddressLock(tempLock.addressLock).isUnlockable(fnftId, uint256(lockId)),
                "E021"
            );

            tempLock.addressLock = address(0);
        }

        tempLock.unlocked = true;

        //Reduce to 1 SSTORE
        locks[lockId] = tempLock;
    }

    /**
     * Return whether a lock of any type is mature. Use this for all locktypes.
     */
    function getLockMaturity(bytes32 lockId, uint256 fnftId) public view override returns (bool hasMatured) {
        ILockManager.Lock memory lock = locks[lockId];

        if (lock.unlocked) return true;

        if (lock.lockType == ILockManager.LockType.TimeLock) {
            hasMatured = lock.timeLockExpiry <= block.timestamp;
        } else if (lock.lockType == ILockManager.LockType.AddressLock) {
            hasMatured = (
                lock.addressLock.supportsInterface(ADDRESS_LOCK_INTERFACE_ID)
                    && IAddressLock(lock.addressLock).isUnlockable(fnftId, uint256(lockId))
            );
        }
        
    }

    function lockTypes(bytes32 tokenId) external view override returns (ILockManager.LockType) {
        return locks[tokenId].lockType;
    }

    function lockExists(bytes32 lockSalt) external view override returns (bool) {
        return locks[lockSalt].creationTime != 0;
    }

    function proxyCallisApproved(
        address token,
        address[] memory targets,
        uint256[] memory, //We don't need values but its in the interface and good for users who want to bring their own lockManager
        bytes[] memory calldatas
    ) external view returns (bool) {
        for (uint256 x = 0; x < calldatas.length;) {
            //Restriction only enabled when the target is the token and not unlocked
            if (targets[x] == token && blacklistedSelector[bytes4(calldatas[x])]) {
                return false;
            }

            //Revest uses address(0) for asset when it is ETH, but stores WETH in the vault.
            //This prevents the edge case for that
            else if (targets[x] == WETH && token == address(0)) {
                console.log("got here");
                if (bytes4(calldatas[x]) == IWETH.withdraw.selector) {
                    return false;
                }
            }

            unchecked {
                ++x;
            }
        }

        return true;
    }
}
