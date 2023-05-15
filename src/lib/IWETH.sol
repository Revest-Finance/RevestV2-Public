// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;
    // Introduced later in development
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}
