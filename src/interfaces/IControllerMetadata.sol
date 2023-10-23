// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

/**
 * @title Provider interface for Revest FNFTs
 */
interface IControllerMetadata {
    //You cannot declare an empty enum in Solidity, so we use this as a placeholder
    enum triggerUpdateType {NONE}

    function triggerUpdate(uint fnftId, triggerUpdateType updateType) external;

    function getCustomMetadata(uint fnftId) external view returns (string memory);
    function getCustomMetadataJSON(uint fnftId) external view returns (bytes memory);
}
