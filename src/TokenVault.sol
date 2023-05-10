// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

import "./RevestSmartWallet.sol";
import "./interfaces/ITokenVault.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

contract TokenVault is ITokenVault, ReentrancyGuard {
    /// Address to use for EIP-1167 smart-wallet creation calls
    address public immutable TEMPLATE;

    constructor() {
        TEMPLATE = address(new RevestSmartWallet());
    }

    function proxyCall(
        bytes32 salt, 
        address[] memory targets, 
        uint256[] memory values, 
        bytes[] memory calldatas
    ) external returns(bytes[] memory outputs) {
        address walletAddr = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender)));
        //Proxy the calls through and selfDestruct itself when finished
        return RevestSmartWallet(walletAddr).proxyCall(targets, values, calldatas);
    }

    function getAddress(
        bytes32 salt, 
        address caller
    ) external view returns (address smartWallet) {
        smartWallet = Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(salt, caller)));
    }


}
