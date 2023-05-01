// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

import "./RevestSmartWallet.sol";
import "./interfaces/ITokenVault.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVault is ITokenVault, Ownable {
    /// Address to use for EIP-1167 smart-wallet creation calls
    address public immutable TEMPLATE;

    mapping(address => bool) public allowedBreakers;
    bool isBroken;

    constructor(
    ) Ownable() {
        RevestSmartWallet wallet = new RevestSmartWallet();
        TEMPLATE = address(wallet);
    }

    modifier glassNotBroken {
        require(!isBroken, "E001");
        _;
    }

    //You can get rid of the deposit function and just have the controller send tokens there directly

    function withdrawToken(
        bytes32 salt,
        address[] memory tokens,
        uint[] memory quantities,
        address recipient //TODO: Can replace user with just send back to msg.sender but less optimized
    ) external override glassNotBroken {
        require(tokens.length == quantities.length);

        //Clone the wallet
        address walletAddr = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender)));
        
        //Withdraw the token, selfDestructs itself after
        RevestSmartWallet(walletAddr).withdraw(tokens, quantities, recipient);

        emit WithdrawERC20(tokens, recipient, salt, quantities, walletAddr);
    }


    function proxyCall(bytes32 salt, address[] memory targets, uint256[] memory values, bytes[] memory calldatas) external glassNotBroken returns(bytes[] memory outputs) {
        address walletAddr = Clones.cloneDeterministic(TEMPLATE, keccak256(abi.encode(salt, msg.sender)));

        //Proxy the calls through and selfDestruct itself when finished
        return RevestSmartWallet(walletAddr).proxyCall(targets, values, calldatas);
    }

    function getFNFTAddress(bytes32 salt, address caller) public view override returns (address smartWallet) {
        smartWallet = Clones.predictDeterministicAddress(TEMPLATE, keccak256(abi.encode(salt, caller)));
    }

    function breakGlass() external {
        require(allowedBreakers[msg.sender]);
        isBroken = true;
    }

    function modifyBreakers(address breaker, bool designation) external onlyOwner {
        allowedBreakers[breaker] = designation;
    }

    function repairGlass() external onlyOwner {
        isBroken = false;
    }
}
