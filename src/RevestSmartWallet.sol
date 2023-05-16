// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "forge-std/console.sol";

pragma solidity ^0.8.12;

contract RevestSmartWallet is ReentrancyGuard {
    using SafeTransferLib for ERC20;

    address private immutable MASTER;

    constructor() {
        MASTER = msg.sender;
    }

    modifier onlyMaster() {
        require(msg.sender == MASTER, "E016");
        _;
    }

    function withdraw(address token, uint256 value, address recipient) external nonReentrant onlyMaster {
        console.log("balance of this: ", ERC20(token).balanceOf(address(this)));
        console.log("value: ", value);

        ERC20(token).safeTransfer(recipient, value);
        cleanMemory();
    }

    function proxyCall(address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
        external
        nonReentrant
        onlyMaster
        returns (bytes[] memory outputs)
    {
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "ER025");
            outputs[i] = result;
        }
    }

    function cleanMemory() public onlyMaster {
        selfdestruct(payable(address(this)));
    }
}
