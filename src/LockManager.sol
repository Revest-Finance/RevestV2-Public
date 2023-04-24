// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/IAddressLock.sol";


contract LockManager is ILockManager, ReentrancyGuard, Ownable {
    using ERC165Checker for address;

    bytes4 public constant ADDRESS_LOCK_INTERFACE_ID = type(IAddressLock).interfaceId;
    mapping(bytes32 => IRevest.Lock) public locks; // maps lockId to locks

    constructor() Ownable() {}


    function getLock(bytes32 lockId) external view override returns (IRevest.Lock memory) {
        bytes32 salt = keccak256(abi.encode(lockId, msg.sender));
        return locks[salt];
    }

    /// NB: The onlyRevest call here dramatically increases gas – should be onlyRevestController
    function createLock(bytes32 salt, IRevest.LockParam memory lock) external override onlyOwner returns (bytes32 lockId) {
        lockId = keccak256(abi.encode(salt, msg.sender));

        // Extensive validation on creation
        require(lock.lockType != IRevest.LockType.DoesNotExist, "E058");
        IRevest.Lock memory newLock = locks[lockId];

        newLock.lockType = lock.lockType;
        newLock.creationTime = block.timestamp;

        if(lock.lockType == IRevest.LockType.TimeLock) {
            require(lock.timeLockExpiry > block.timestamp, "E002");
            newLock.timeLockExpiry = lock.timeLockExpiry;
        }
       
        else if (lock.lockType == IRevest.LockType.AddressLock) {
            require(lock.addressLock != address(0), "E004");
            newLock.addressLock = lock.addressLock;
        }

        else {
            require(false, "Invalid type");
        }

        //Use a single SSTORE
        locks[lockId] = newLock;
      
    }

    /**
     * @dev Sets the maturity of an address or value lock to mature – can only be called from main contract
     * if address, only if it is called by the address given permissions to
     * if value, only if value is correct for unlocking
     * lockId - the ID of the FNFT to unlock
     * @return true if the caller is valid and the lock has been unlocked, false otherwise
     */
    function unlockFNFT(bytes32 salt, uint fnftId, address sender) external override onlyOwner returns (bool) {
        bytes32 lockId = keccak256(abi.encode(salt, msg.sender));

        //Allows reduction to 1 SSTORE at the end as opposed to many
        IRevest.Lock memory tempLock = locks[lockId];
        IRevest.LockType lockType = tempLock.lockType;
        if (lockType == IRevest.LockType.TimeLock) {
            if(!tempLock.unlocked && tempLock.timeLockExpiry <= block.timestamp) {
                tempLock.unlocked = true;
                tempLock.timeLockExpiry = 0;
            }
        }
      
        else if (lockType == IRevest.LockType.AddressLock) {
            address addLock = tempLock.addressLock;
            if (!tempLock.unlocked && (sender == addLock ||
                    (addLock.supportsInterface(ADDRESS_LOCK_INTERFACE_ID) && IAddressLock(addLock).isUnlockable(fnftId, uint(lockId))))
                ) {
                tempLock.unlocked = true;
                tempLock.addressLock = address(0);
            }
        }

        //Reduce to 1 SSTORE
        locks[lockId] = tempLock;

        return tempLock.unlocked;
    }

    /**
     * Return whether a lock of any type is mature. Use this for all locktypes.
     */
    function getLockMaturity(bytes32 salt, uint fnftId) public view override returns (bool) {
        bytes32 lockId = keccak256(abi.encode(salt, msg.sender));
        
        IRevest.Lock memory lock = locks[lockId];
        if (lock.lockType == IRevest.LockType.TimeLock) {
            return lock.unlocked || lock.timeLockExpiry < block.timestamp;
        }
     
        else if (lock.lockType == IRevest.LockType.AddressLock) {
            return lock.unlocked || (lock.addressLock.supportsInterface(ADDRESS_LOCK_INTERFACE_ID) &&
                                        IAddressLock(lock.addressLock).isUnlockable(fnftId, uint(lockId)));
        }
        else {
            revert("E050");
        }
    }

    function lockTypes(bytes32 tokenId) external view override returns (IRevest.LockType) {
        bytes32 salt = keccak256(abi.encode(tokenId, msg.sender));
        return locks[salt].lockType;
    }

 

}
