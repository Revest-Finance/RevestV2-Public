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
        if (token == address(0)) {
            recipient.safeTransferETH(value);
        }
        
        else {
            ERC20(token).safeTransfer(recipient, value);
        }

        
        _cleanMemory();
    }

    /**
     * @notice Allows for arbitrary calls to be made via the assets stored in this contract
     * @param targets the contract(s) to target for the list of calls
     * @param values The Ether values to transfer (typically zero)
     * @param calldatas Encoded calldata for each function
     * @dev Calldata must be properly encoded and function selectors must be on the whitelist for this method to function. Functions cannot transfer tokens out
     */
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
