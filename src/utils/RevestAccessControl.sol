// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IAddressRegistry.sol";
import "../interfaces/ILockManager.sol";
import "../interfaces/IRewardsHandler.sol";
import "../interfaces/ITokenVault.sol";
import "../interfaces/IFNFTHandler.sol";


contract RevestAccessControl is Ownable {
    IAddressRegistry internal addressesProvider;

    constructor(address provider) Ownable() {
        addressesProvider = IAddressRegistry(provider);
    }

    modifier onlyRevest() {
        require(_msgSender() != address(0), "E004");
        require(
                _msgSender() == addressesProvider.getLockManager() ||
                _msgSender() == addressesProvider.getRewardsHandler() ||
                _msgSender() == addressesProvider.getTokenVault() ||
                _msgSender() == addressesProvider.getRevest() ||
                _msgSender() == addressesProvider.getRevestToken(),
            "E016"
        );
        _;
    }

    modifier onlyRevestController() {
        require(_msgSender() != address(0), "E004");
        require(_msgSender() == addressesProvider.getRevest(), "E017");
        _;
    }

    modifier onlyTokenVault() {
        require(_msgSender() != address(0), "E004");
        require(_msgSender() == addressesProvider.getTokenVault(), "E017");
        _;
    }

    function setAddressRegistry(address registry) external onlyOwner {
        addressesProvider = IAddressRegistry(registry);
    }

    function getAdmin() internal view returns (address) {
        return addressesProvider.getAdmin();
    }

    function getRevest() internal view returns (IRevest) {
        return IRevest(addressesProvider.getRevest());
    }

    function getRevestToken() internal view returns (IERC20) {
        return IERC20(addressesProvider.getRevestToken());
    }

    function getLockManager() internal view returns (ILockManager) {
        return ILockManager(addressesProvider.getLockManager());
    }

    function getTokenVault() internal view returns (ITokenVault) {
        return ITokenVault(addressesProvider.getTokenVault());
    }

    function getFNFTHandler() internal view returns (IFNFTHandler) {
        return IFNFTHandler(addressesProvider.getRevestFNFT());
    }

    function getRewardsHandler() internal view returns (IRewardsHandler) {
        return IRewardsHandler(addressesProvider.getRewardsHandler());
    }
}