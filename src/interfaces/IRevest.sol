// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "./IController.sol";

pragma solidity ^0.8.12;

interface IRevest is IController {
    function mintTimeLockWithPermit(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);

    function mintTimeLock(
        uint256 endTime,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (bytes32, bytes32);

    function mintAddressLock(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig
    ) external payable returns (bytes32, bytes32);

    function mintAddressLockWithPermit(
        address trigger,
        bytes memory arguments,
        address[] memory recipients,
        uint256[] memory quantities,
        IRevest.FNFTConfig memory fnftConfig,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external payable returns (bytes32, bytes32);
}
