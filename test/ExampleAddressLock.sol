// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity <=0.8.19;

import "src/interfaces/IAddressLock.sol";

contract ExampleAddressLock is IAddressLock {
    function supportsInterface(bytes4 selector) external pure returns (bool) {
        return selector == type(IAddressLock).interfaceId;
    }

    function createLock(uint256, uint256, bytes memory) external pure {}

    function updateLock(uint256, uint256, bytes memory) external pure {}

    function isUnlockable(uint256, uint256) external view returns (bool) {
        //Makes Testing Easier
        return block.timestamp % 2 == 0;
    }

    function getDisplayValues(uint256, uint256) external pure returns (bytes memory) {
        return "";
    }

    function getMetadata() external pure returns (string memory) {
        return "";
    }

    function needsUpdate() external pure returns (bool) {
        return false;
    }
}
