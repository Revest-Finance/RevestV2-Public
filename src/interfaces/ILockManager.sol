// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "./IRevest.sol";

interface ILockManager {
    function createLock(bytes32 fnftId, IRevest.LockParam memory lock) external returns (bytes32);

    function getLock(bytes32 lockId) external view returns (IRevest.Lock memory);

    function lockTypes(bytes32 fnftId) external view returns (IRevest.LockType);

    function unlockFNFT(bytes32 salt, uint256 fnftId, address caller) external;

    function getLockMaturity(bytes32 salt, uint256 fnftId) external view returns (bool);

    function lockExists(bytes32 lockSalt) external view returns (bool);

    function proxyCallisApproved(
        bytes32 salt,
        address token,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) external view returns (bool);
}
