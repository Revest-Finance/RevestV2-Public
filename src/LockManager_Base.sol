// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { IRevest } from "./interfaces/IRevest.sol";
import { ILockManager } from "./interfaces/ILockManager.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title LockManager_Base
 * @author 0xTraub
 */
abstract contract LockManager_Base is ILockManager, ReentrancyGuard {

    mapping(bytes32 => ILockManager.Lock) public locks; // maps lockId to locks

    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {
       
    }

    function getLock(bytes32 salt) external view virtual returns (ILockManager.Lock memory) {
        return locks[salt];
    }

    /**
     * @dev Sets the maturity of an address or value lock to mature – can only be called from main contract
     * if address, only if it is called by the address given permissions to
     * if value, only if value is correct for unlocking
     * lockId - the ID of the FNFT to unlock
     */
    function unlockFNFT(bytes32 lockId, uint256 fnftId) external virtual nonReentrant {
        //Allows reduction to 1 SSTORE at the end as opposed to many
        ILockManager.Lock memory tempLock = locks[lockId];

        require(tempLock.creationTime != 0, "E016");

        //If already unlocked, no state changes needed
        if (tempLock.unlocked) return;

        require(getLockMaturity(lockId, fnftId), "E006");

        tempLock.unlocked = true;

        //Reduce to 1 SSTORE
        locks[lockId] = tempLock;
    }

    function getLockMaturity(bytes32 salt, uint256 fnftId) public view virtual returns (bool);

    function lockExists(bytes32 lockSalt) external view virtual returns (bool) {
        return locks[lockSalt].creationTime != 0;
    }

    function getMetadata(bytes32) external view returns (string memory) {
        return "TODO";
    }

    function lockDescription(bytes32) external view virtual returns (string memory) {
        return "LockManager_Base";
    }
}
