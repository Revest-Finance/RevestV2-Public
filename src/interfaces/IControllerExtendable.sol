// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "./IAllowanceTransfer.sol";

/**
 * @title Provider interface for Revest FNFTs
 */
interface IControllerExtendable {
    event FNFTMaturityExtended(
        bytes32 indexed newLockId, address from, uint256 indexed fnftId, uint256 indexed newExtendedTime
    );

    event FNFTAddionalDeposited(
        address indexed from, uint256 indexed newFNFTId, uint256 indexed quantity, uint256 mount
    );

    function depositAdditionalToFNFT(bytes32 salt, uint256 amount) external payable returns (uint256);
    function depositAdditionalToFNFTWithPermit(
        bytes32 salt,
        uint256 amount,
        IAllowanceTransfer.PermitBatch calldata permits,
        bytes calldata _signature
    ) external returns (uint256);

    function extendFNFTMaturity(bytes32 salt, uint256 endTime) external ;
}
