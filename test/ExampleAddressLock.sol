// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;


import "src/interfaces/IAddressLock.sol";

contract ExampleAddressLock is IAddressLock {

    function supportsInterface(bytes4 selector) external pure returns (bool) {
        return selector == type(IAddressLock).interfaceId;
    }
    
    function createLock(uint, uint, bytes memory) external pure {}

    
    function updateLock(uint, uint, bytes memory) external pure {}

    
    function isUnlockable(uint, uint) external view returns (bool) {
        //Makes Testing Easier
        return block.timestamp % 2 == 0;
    }

    
    function getDisplayValues(uint, uint) external pure returns (bytes memory) {
        return "";
    }

    
    function getMetadata() external pure returns (string memory) {
        return "";
    }

    function needsUpdate() external pure returns (bool) {
        return false;
    }
}