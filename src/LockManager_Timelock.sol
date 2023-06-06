// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./lib/IWETH.sol";

import "./LockManager_Base.sol";

import "forge-std/console.sol";

contract LockManager_Timelock is LockManager_Base {

    ILockManager.LockType public constant override lockType = ILockManager.LockType.TimeLock;

    constructor(address _WETH) LockManager_Base(_WETH) {
    }
     

    function createLock(bytes32 salt, bytes calldata args)
        external
        override
        nonReentrant
        returns (bytes32 lockId)
    {
        lockId = keccak256(abi.encode(salt, msg.sender));

        // Extensive validation on creation
        ILockManager.Lock memory newLock;

        newLock.creationTime = block.timestamp;
        newLock.creator = msg.sender;

        uint timeLockExpiry = abi.decode(args, (uint));

        console.log("timestamp: ", block.timestamp);

        require(timeLockExpiry > block.timestamp, "E015");
        newLock.timeLockExpiry = timeLockExpiry;

        //Use a single SSTORE
        locks[lockId] = newLock;
    }


    /**
     * Return whether a lock of any type is mature. Use this for all locktypes.
     */
    function getLockMaturity(bytes32 lockId, uint) public view override returns (bool hasMatured) {
        ILockManager.Lock memory lock = locks[lockId];

        if (lock.unlocked) return true;

        hasMatured = (lock.timeLockExpiry <= block.timestamp);

    }

    function getTimeRemaining(bytes32 lockId, uint) public view returns (uint256) {
        ILockManager.Lock memory lock = locks[lockId];

        if (lock.unlocked || lock.timeLockExpiry == 0) return 0;

        else return lock.timeLockExpiry - block.timestamp;
    }
    
}
