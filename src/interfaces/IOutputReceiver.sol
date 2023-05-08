// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/introspection/IERC165.sol';

/**
 * @title Provider interface for Revest FNFTs
 */
interface IOutputReceiver is IERC165 {
    event DepositERC20OutputReceiver(address indexed mintTo, address indexed token, uint amountTokens, uint indexed fnftId, bytes extraData);

    event DepositERC721OutputReceiver(address indexed mintTo, address indexed token, uint[] tokenIds, uint indexed fnftId, bytes extraData);

    event DepositERC1155OutputReceiver(address indexed mintTo, address indexed token, uint tokenId, uint amountTokens, uint indexed fnftId, bytes extraData);

    event WithdrawERC20OutputReceiver(address indexed caller, address indexed token, uint amountTokens, uint indexed fnftId, bytes extraData);

    event WithdrawERC721OutputReceiver(address indexed caller, address indexed token, uint[] tokenIds, uint indexed fnftId, bytes extraData);

    event WithdrawERC1155OutputReceiver(address indexed caller, address indexed token, uint tokenId, uint amountTokens, uint indexed fnftId, bytes extraData);

    event TransferERC20OutputReceiver(address indexed transferTo, address indexed transferFrom, address indexed token, uint amountTokens, uint fnftId, bytes extraData);

    event TransferERC721OutputReceiver(address indexed transferTo, address indexed transferFrom, address indexed token, uint[] tokenIds, uint fnftId, bytes extraData);

    event TransferERC1155OutputReceiver(address indexed transferTo, address indexed transferFrom, address indexed token, uint tokenId, uint amountTokens, uint fnftId, bytes extraData);

    function receiveRevestOutput(
        uint fnftId,
        address asset,
        address payable owner,
        uint quantity
    ) external;

    function getCustomMetadata(uint fnftId) external view returns (string memory);

    function getValue(uint fnftId) external view returns (uint);

    function getAsset(uint fnftId) external view returns (address);

    function getOutputDisplayValues(uint fnftId) external view returns (bytes memory);

    function handleTimelockExtensions(uint fnftId, uint expiration, address caller) external;

    function handleAdditionalDeposit(uint fnftId, uint amount, uint quantity, address caller) external;

    function onTransferFNFT(
        uint fnftId, 
        address operator,
        address from,
        address to,
        uint quantity, 
        bytes memory data
    ) external;
}
