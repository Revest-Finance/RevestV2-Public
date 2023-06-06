// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./lib/IWETH.sol";

import "forge-std/console.sol";

abstract contract LockManager_Base is ILockManager, ReentrancyGuard {
    using ERC165Checker for address;

    mapping(bytes32 => ILockManager.Lock) public locks; // maps lockId to locks

    mapping(bytes4 selector => bool) public blacklistedSelector;

    address public immutable WETH;

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

    function getLockMaturity(bytes32 salt, uint fnftId) public virtual view returns (bool);

    function lockExists(bytes32 lockSalt) external virtual view returns (bool) {
        return locks[lockSalt].creationTime != 0;
    }

    function proxyCallisApproved(
        address token,
        address[] memory targets,
        uint256[] memory, //We don't need values but its in the interface and good for users who want to bring their own lockManager
        bytes[] memory calldatas
    ) external virtual view returns (bool) {
        for (uint256 x = 0; x < calldatas.length;) {

            //TODO: Determine if potential security issue
            // //No Calling EOAs
            // if (targets[x].code.length == 0) return false;

            console.log("targets[x]: %s", targets[x]);
            console.log("token: %s", token);

            //Restriction only enabled when the target is the token and not unlocked
            if (targets[x] == token && blacklistedSelector[bytes4(calldatas[x])]) {
                return false;
            }
            //Revest uses address(0) for asset when it is ETH, but stores WETH in the vault.
            //This prevents the edge case for that

            else if (targets[x] == WETH && token == address(0xdead)) {
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
