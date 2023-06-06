// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "./IRevest.sol";

interface ILockManager {
    enum LockType {
        DEFAULT,
        TimeLock,
        AddressLock
    }

    struct Lock {
        address creator;
        bool unlocked;
        uint256 timeLockExpiry;
        uint256 creationTime;
    }


    function createLock(bytes32 fnftId, bytes calldata args) external returns (bytes32);

    function getLock(bytes32 lockId) external view returns (Lock memory);

    function lockType() external view returns (LockType);

    function unlockFNFT(bytes32 salt, uint256 fnftId) external;

    function getLockMaturity(bytes32 salt, uint fnftId) external view returns (bool);

    function lockExists(bytes32 lockSalt) external view returns (bool);

    function proxyCallisApproved(
        address token,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) external view returns (bool);

}
