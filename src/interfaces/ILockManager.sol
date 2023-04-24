// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity >=0.8.0;

import "./IRevest.sol";

interface ILockManager {

    function createLock(bytes32 fnftId, IRevest.LockParam memory lock) external returns (bytes32);

    function getLock(bytes32 lockId) external view returns (IRevest.Lock memory);

    function lockTypes(bytes32 fnftId) external view returns (IRevest.LockType);

    function unlockFNFT(bytes32 salt, uint fnftId, address sender) external returns (bool);

    function getLockMaturity(bytes32 salt, uint fnftId) external view returns (bool);
}
