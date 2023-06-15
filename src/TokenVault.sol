// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;
pragma experimental ABIEncoderV2;

import "./RevestSmartWallet.sol";
import "./interfaces/ITokenVault.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenVault
 * @author 0xTraub
 */
contract TokenVault is ITokenVault, ReentrancyGuard {
    /// Address to use for EIP-1167 smart-wallet creation calls
    address public immutable TEMPLATE;

    constructor() {
        TEMPLATE = address(new RevestSmartWallet());
    }

    //You can get rid of the deposit function and just have the controller send tokens there directly

    function withdrawToken(
        bytes32 salt,
        bytes calldata data
    ) external override nonReentrant {
        address payable walletAddr =
            payable(Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender))));

        //Withdraw the token, selfDestructs itself after
        RevestSmartWallet(walletAddr).withdraw(msg.sender, data);
        
        //TODO: Better Event Handling
        // emit WithdrawERC20(token, recipient, salt, quantity, walletAddr);
    }

    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
        external
        nonReentrant
        returns (bytes[] memory outputs)
    {
        address payable walletAddr =
            payable(Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender))));

        //Proxy the calls through and selfDestruct itself when finished
        outputs = RevestSmartWallet(walletAddr).proxyCall(targets, values, calldatas);

        //Making separate call prevents selfDestruct returndata bug
        RevestSmartWallet(walletAddr).cleanMemory();
    }

    function getAddress(bytes32 salt, address caller) external view returns (address smartWallet) {
        smartWallet = Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(salt, caller)));
    }
}
