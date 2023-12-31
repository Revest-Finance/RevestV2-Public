// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "./IController.sol";
import "./IAllowanceTransfer.sol";

pragma solidity ^0.8.12;

interface IRevest is IController {
    event FNFTTimeLockMinted(
        address indexed asset,
        address indexed from,
        uint256 indexed fnftId,
        uint256 endTime,
        uint256[] quantities,
        FNFTConfig fnftConfig
    );

    event FNFTAddressLockMinted(
        address indexed asset, address indexed from, uint256 indexed fnftId, uint256[] quantities, FNFTConfig fnftConfig
    );

    function mintTimeLockWithPermit(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (uint, bytes32);

    function mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (uint, bytes32);

    function mintAddressLock(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (uint, bytes32);

    function mintAddressLockWithPermit(
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        uint256 depositAmount,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (uint, bytes32);
}
