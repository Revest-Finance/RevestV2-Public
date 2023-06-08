// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

interface IMetadataHandler {
    function getTokenURI(bytes32 fnftId) external view returns (string memory);

    function setTokenURI(bytes32 fnftId, string memory _uri) external;

    function getRenderTokenURI(bytes32 tokenId, address owner)
        external
        view
        returns (string memory baseRenderURI, string[] memory parameters);

    function setRenderTokenURI(bytes32 tokenID, string memory baseRenderURI) external;
}
