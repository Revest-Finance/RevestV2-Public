// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

contract RevestSmartWallet {

    address private immutable MASTER;

    constructor() {
        MASTER = msg.sender;
    }

    function proxyCall(address[] memory targets, uint256[] memory values, bytes[] memory calldatas) external returns(bytes[] memory outputs) {
        require(msg.sender == MASTER, 'E016');
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "ER022");
            outputs[i] = result;
        }

        // Must manually cleanup since this returns something
        selfdestruct(payable(MASTER));
    }

}
