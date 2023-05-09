// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/IAddressLock.sol";


contract LockManager is ILockManager, ReentrancyGuard {
    using ERC165Checker for address;

    bytes4 public constant ADDRESS_LOCK_INTERFACE_ID = type(IAddressLock).interfaceId;
    mapping(bytes32 => IRevest.Lock) public locks; // maps lockId to locks

    function getLock(bytes32 lockId) external view override returns (IRevest.Lock memory) {
        bytes32 salt = keccak256(abi.encode(lockId, msg.sender));
        return locks[salt];
    }

    function createLock(bytes32 salt, IRevest.LockParam memory lock) external override nonReentrant returns (bytes32 lockId) {
        lockId = keccak256(abi.encode(salt, msg.sender));

        // Extensive validation on creation
        IRevest.Lock memory newLock = locks[lockId];

        newLock.lockType = lock.lockType;
        newLock.creationTime = block.timestamp;

        if(lock.lockType == IRevest.LockType.TimeLock) {
            require(lock.timeLockExpiry > block.timestamp, "E015");
            newLock.timeLockExpiry = lock.timeLockExpiry;
        }
       
        else if (lock.lockType == IRevest.LockType.AddressLock) {
            require(lock.addressLock != address(0), "E016");
            newLock.addressLock = lock.addressLock;
        }

        else {
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
    function unlockFNFT(bytes32 salt, uint fnftId, address sender) external override nonReentrant {
        bytes32 lockId = keccak256(abi.encode(salt, msg.sender));

        //Allows reduction to 1 SSTORE at the end as opposed to many
        IRevest.Lock memory tempLock = locks[lockId];

        //If already unlocked, no state changes needed
        if (tempLock.unlocked) return;

        if (tempLock.lockType == IRevest.LockType.TimeLock) {
            require(tempLock.timeLockExpiry <= block.timestamp, "E015");
            tempLock.timeLockExpiry = 0;
        }
      
        else if (tempLock.lockType == IRevest.LockType.AddressLock) {
            require((sender == tempLock.addressLock) ||
                    (tempLock.addressLock.supportsInterface(ADDRESS_LOCK_INTERFACE_ID) 
                    && IAddressLock(tempLock.addressLock).isUnlockable(fnftId, uint(lockId))));

                tempLock.addressLock = address(0);
        }

        else {
            revert("E017");
        }

        tempLock.unlocked = true;

        //Reduce to 1 SSTORE
        locks[lockId] = tempLock;
    }

    /**
     * Return whether a lock of any type is mature. Use this for all locktypes.
     */
    function getLockMaturity(bytes32 salt, uint fnftId) public view override returns (bool) {
        bytes32 lockId = keccak256(abi.encode(salt, msg.sender));
        
        IRevest.Lock memory lock = locks[lockId];

        if (lock.unlocked) return true;

        if (lock.lockType == IRevest.LockType.TimeLock) {
            return lock.timeLockExpiry < block.timestamp;
        }
     
        else if (lock.lockType == IRevest.LockType.AddressLock) {
            return (lock.addressLock.supportsInterface(ADDRESS_LOCK_INTERFACE_ID) &&
                    IAddressLock(lock.addressLock).isUnlockable(fnftId, uint(lockId)));
        }

        else {
            return false;
        }
    }

    function lockTypes(bytes32 tokenId) external view override returns (IRevest.LockType) {
        bytes32 salt = keccak256(abi.encode(tokenId, msg.sender));
        return locks[salt].lockType;
    }

    function lockExists(bytes32 lockSalt) external view override returns (bool) {
        return locks[lockSalt].creationTime != 0;
    }

}
