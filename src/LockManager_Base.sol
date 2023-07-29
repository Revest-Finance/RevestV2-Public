// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./lib/IWETH.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title LockManager_Base
 * @author 0xTraub
 */
abstract contract LockManager_Base is ILockManager, ReentrancyGuard {
    using ERC165Checker for address;

    mapping(bytes32 => ILockManager.Lock) public locks; // maps lockId to locks

    mapping(bytes4 selector => bool) public blacklistedSelector;

    address public immutable WETH;

    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address _WETH) {
        blacklistedSelector[IERC20.transfer.selector] = true;
        blacklistedSelector[IERC20.approve.selector] = true;
        blacklistedSelector[IERC20.transferFrom.selector] = true;
        WETH = _WETH;
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
