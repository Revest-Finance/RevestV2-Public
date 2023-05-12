// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

pragma solidity ^0.8.12;

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

interface IFNFTHandler is IERC1155, IERC1155Supply {
  struct permitApprovalInfo {
    address owner;
    address operator;
    uint id;
    uint amount;
    uint256 deadline;
    bytes data;
  }

  function mint(address account, uint id, uint amount, bytes memory data) external;

  function burn(address account, uint id, uint amount) external;

  function getNextId() external view returns (uint);
}
