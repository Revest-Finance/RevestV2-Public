// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRevest.sol";
import "./lib/IWETH.sol";

import "./LockManager_Base.sol";

/**
 * @title LockManager_Addresslock
 * @author 0xTraub
 */
contract LockManager_Addresslock is LockManager_Base {
    using ERC165Checker for address;

    ILockManager.LockType public constant override lockType = ILockManager.LockType.AddressLock;

    constructor(address _WETH) LockManager_Base(_WETH) {}

    function createLock(bytes32 salt, bytes calldata) external override nonReentrant returns (bytes32 lockId) {
        lockId = keccak256(abi.encode(salt, msg.sender));

        // Extensive validation on creation
        ILockManager.Lock memory newLock;

        newLock.creationTime = uint96(block.timestamp);

        //Use a single SSTORE
        locks[lockId] = newLock;
    }

    /**
     * Return whether a lock of any type is mature. Use this for all locktypes.
     */
    function getLockMaturity(bytes32, uint256) public view override returns (bool hasMatured) {
        //Note: Can be replaced with any logic you want I just have this for the tests
        return (block.timestamp % 2 == 0);
    }
}
