// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

pragma solidity ^0.8.19;

interface IERC1155Supply {
    // @notice      This function MUST return whether the given token id exists, previously existed, or may exist
    // @param   id  The token id of which to check the existence
    // @return      Whether the given token id exists, previously existed, or may exist
    function exists(uint256 id) external view returns (bool);

    // @notice      This function MUST return the number of tokens with a given id. If the token id does not exist, it MUST return 0.
    // @param   id  The token id of which fetch the total supply
    // @return      The total supply of the given token id
    function totalSupply(uint256 id) external view returns (uint256);
}

interface IFNFTHandler is IERC165, IERC1155, IERC1155Supply {
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    struct permitApprovalInfo {
        address owner;
        address operator;
        uint256 id;
        uint256 amount;
        uint256 deadline;
        bytes data;
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external;

    function burn(address account, uint256 id, uint256 amount) external;

    function getNextId() external view returns (uint256);

    function uri(uint256 fnftId) external view returns (string memory);

    function renderTokenURI(uint256 tokenId, address owner)
        external
        view
        returns (string memory baseRenderURI, string[] memory parameters);
}
