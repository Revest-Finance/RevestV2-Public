// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./RevestSmartWallet.sol";
import "./interfaces/ITokenVault.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";

import "@solmate/utils/SafeTransferLib.sol";


contract TokenVault is ITokenVault {
    /// Address to use for EIP-1167 smart-wallet creation calls
    address public immutable TEMPLATE;

    constructor(
    ) {
        RevestSmartWallet wallet = new RevestSmartWallet();
        TEMPLATE = address(wallet);
    }

    //You can get rid of the deposit function and just have the controller send tokens there directly

    function withdrawToken(
        bytes32 salt,
        address token,
        uint quantity,
        address recipient //TODO: Can replace user with just send back to msg.sender?
    ) external override {

        //Clone the wallet
        address walletAddr = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender)));
        
        //Withdraw the token, selfDestructs itself after
        RevestSmartWallet(walletAddr).withdraw(token, quantity, recipient);

        emit WithdrawERC20(token, recipient, salt, quantity, walletAddr);
    }


    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) external returns(bytes[] memory outputs) {
        address walletAddr = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender)));

        //Proxy the calls through and selfDestruct itself when finished
        return RevestSmartWallet(walletAddr).proxyCall(targets, values, calldatas);

    }

    function getFNFTAddress(bytes32 salt) public view override returns (address smartWallet) {
        smartWallet = Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(salt, msg.sender)));
    }
}
