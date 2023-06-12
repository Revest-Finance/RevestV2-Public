// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";
import "./lib/IWETH.sol";

import "./LockManager_Base.sol";

import "./lib/DateTime.sol";
/**
 * @title LockManager_Timelock
 * @author 0xTraub
 */
contract LockManager_Timelock is LockManager_Base {
    using DateTime for uint256;
    using DateTime for uint8;
    using Strings for *;

    ILockManager.LockType public constant override lockType = ILockManager.LockType.TimeLock;

    constructor(address _WETH) LockManager_Base(_WETH) {}

    function createLock(bytes32 salt, bytes calldata args) external override nonReentrant returns (bytes32 lockId) {
        lockId = keccak256(abi.encode(salt, msg.sender));

        // Extensive validation on creation
        ILockManager.Lock memory newLock;

        newLock.creationTime = block.timestamp;
        newLock.creator = msg.sender;

        uint256 timeLockExpiry = abi.decode(args, (uint256));

        require(timeLockExpiry > block.timestamp, "E015");
        newLock.timeLockExpiry = timeLockExpiry;

        //Use a single SSTORE
        locks[lockId] = newLock;
    }

    /**
     * Return whether a lock of any type is mature. Use this for all locktypes.
     */
    function getLockMaturity(bytes32 lockId, uint256) public view override returns (bool hasMatured) {
        ILockManager.Lock memory lock = locks[lockId];

        if (lock.unlocked) return true;

        hasMatured = (lock.timeLockExpiry <= block.timestamp);
    }

    function getTimeRemaining(bytes32 lockId, uint256) public view returns (uint256) {
        ILockManager.Lock memory lock = locks[lockId];

        if (lock.unlocked || lock.timeLockExpiry == 0) return 0;
        else return lock.timeLockExpiry - block.timestamp;
    }

    function lockDescription(bytes32 lockId) public view virtual override returns (string memory) {
        ILockManager.Lock memory lock = locks[lockId];

        (uint8 day, uint8 month, uint16 year, uint8 _hour, uint8 _minute) = lock.timeLockExpiry.parseTimestamp();

        string memory minute;
        if (_minute < 10) minute = string.concat('0', _minute.toString());
        else minute = _minute.toString();

        string memory hour;
        if (_hour > 12) hour = (_hour % 12).toString();
        else hour = _hour.toString();

        string memory description = string.concat(
            '<text x="50%" y="210" dy= "210" dominant-baseline="middle" text-anchor="middle" class="underLine" fill="#fff"> ',
            'Unlocks: ',
            month.getMonthName(),
            ' ',
            day.toString(),
            ', ',
            year.toString(),
            ' ',
            hour,
            ':',
            minute
        );

        if (_hour >= 12) return string.concat(description, ' PM</text>');
        else return string.concat(description, ' AM</text>');
    }

    
}
