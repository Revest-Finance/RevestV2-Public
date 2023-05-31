// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMetadataHandler.sol";

contract MetadataHandler is Ownable, IMetadataHandler {
    string public uri;
    string public renderURI;

    constructor(string memory _uri) Ownable() {
        uri = _uri;
    }

    function getTokenURI(uint256 fnftId) external view override returns (string memory) {
        return string(abi.encodePacked(uri, uint2str(fnftId), "&chainId=", uint2str(block.chainid)));
    }

    function setTokenURI(uint256, string memory _uri) external override onlyOwner {
        uri = _uri;
    }

    function getRenderTokenURI(uint256, address)
        external
        view
        override
        returns (string memory, string[] memory parameters)
    {
        string[] memory arr;
        return (renderURI, arr);
    }

    function setRenderTokenURI(uint256, string memory baseRenderURI) external override onlyOwner {
        renderURI = baseRenderURI;
    }

    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
