// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity >=0.8.0;

import "./IRevest.sol";

interface ITokenVault {

    /// Emitted when an FNFT is withdraw  to denote what tokens have been withdrawn
    event WithdrawERC20(address[] indexed tokens, address indexed user, bytes32 indexed salt, uint[] tokenAmounts, address smartWallet);

    function withdrawToken(
        bytes32 salt,
        address[] memory token,
        uint[] memory quantities,
        address recipient //TODO: Can replace user with just send back to msg.sender?
    ) external;

    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) external returns(bytes[] memory outputs);

    function getFNFTAddress(bytes32 salt) external view returns (address smartWallet);
    
}
