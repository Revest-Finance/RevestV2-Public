// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "src/interfaces/IAddressLock.sol";

import "forge-std/console.sol";

contract ExampleAddressLock is IAddressLock {
    //TODO Change back to Pure when testing is done
    function supportsInterface(bytes4 selector) public pure override returns (bool) {
        return selector == type(IAddressLock).interfaceId || selector == type(IERC165).interfaceId;
    }

    function createLock(uint256, uint256, bytes memory) external pure {}

    function isUnlockable(uint256, uint256) external view returns (bool) {
        console.log("block timestamp: %i", block.timestamp);
        //Makes Testing Easier
        return block.timestamp % 2 == 0;
    }

  
}
