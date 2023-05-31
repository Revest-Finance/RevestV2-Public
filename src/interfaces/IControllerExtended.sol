// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title Provider interface for Revest FNFTs
 */
interface IControllerExtended is IERC165 {
    //You cannot declare an empty enum in Solidity, so we use this as a placeholder
    enum triggerUpdateType {NONE}

    function getCustomMetadata(uint256 fnftId) external view returns (string memory);
    function getCustomMetadataJSON(uint256 fnftId) external view returns (bytes memory);
}
