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

    function getAddress(bytes32 salt, address caller) external view returns (address smartWallet);
    function getAddressForFNFT(address handler, uint fnftId, address caller) external view returns (address smartWallet);

    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) external returns(bytes[] memory outputs);

}
