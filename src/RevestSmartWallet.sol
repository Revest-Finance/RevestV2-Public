// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

pragma solidity ^0.8.19;

/** @title RevestSmartWallet
 * @author 0xTraub
 */
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
        ERC20(token).safeTransfer(recipient, value);
        cleanMemory();
    }

    function proxyCall(address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
        external
        nonReentrant
        onlyMaster
        returns (bytes[] memory outputs)
    {
        outputs = new bytes[](targets.length);

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "E025");
            outputs[i] = result;
        }
    }

    function cleanMemory() public onlyMaster {
        selfdestruct(payable(address(this)));
    }

    //We want to be able to receive ETH for any other misc. things people want to do with it.
    fallback() external payable {}
    receive() external payable {}
}
