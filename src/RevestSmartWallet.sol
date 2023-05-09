// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

pragma solidity ^0.8.12;

contract RevestSmartWallet is ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for address;

    address private immutable MASTER;

    constructor() {
        MASTER = msg.sender;
    }

    modifier onlyMaster() {
        require(msg.sender == MASTER, 'E016');
        _;
    }

    function withdraw(address token, uint value, address recipient) external nonReentrant onlyMaster {
        ERC20(token).safeTransfer(recipient, value);
        _cleanMemory();
    }


    function _cleanMemory() internal {
        selfdestruct(payable(MASTER));
    }

}
