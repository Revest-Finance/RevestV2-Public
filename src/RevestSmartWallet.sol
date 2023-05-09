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

    function proxyCall(address[] memory targets, uint256[] memory values, bytes[] memory calldatas) external nonReentrant onlyMaster returns(bytes[] memory outputs) {
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "ER022");
            outputs[i] = result;
        }

        // Must manually cleanup since this returns something
        _cleanMemory();
    }


    function _cleanMemory() internal {
        selfdestruct(payable(MASTER));
    }

}
