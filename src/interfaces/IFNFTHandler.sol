// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

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

interface IFNFTHandler is IERC1155Supply, IERC1155 {
    function mint(address account, uint id, uint amount, bytes memory data) external;

    function mintBatchRec(address[] memory recipients, uint[] memory quantities, uint id, uint newSupply, bytes memory data) external;

    function mintBatch(address to, uint[] memory ids, uint[] memory amounts, bytes memory data) external;

    function burn(address account, uint id, uint amount) external;

    function getNextId() external view returns (uint);
}
