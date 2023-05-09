// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "./IRevest.sol";

interface ITokenVault {

    /// Emitted when an FNFT is withdraw  to denote what tokens have been withdrawn
    event WithdrawERC20(address token, address indexed user, bytes32 indexed salt, uint amount, address smartWallet);

    function withdrawToken(
        bytes32 salt,
        address token,
        uint quantity,
        address recipient //TODO: Can replace user with just send back to msg.sender but less optimized
    ) external;

    function getFNFTAddress(bytes32 salt, address caller) external view returns (address smartWallet);
    
}
