// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title Provider interface for Revest FNFTs
 */
interface IOutputReceiver is IERC165 {
    event DepositERC20OutputReceiver(
        address indexed mintTo, address indexed token, uint256 amountTokens, uint256 indexed fnftId, bytes extraData
    );

    event DepositERC721OutputReceiver(
        address indexed mintTo, address indexed token, uint256[] tokenIds, uint256 indexed fnftId, bytes extraData
    );

    event DepositERC1155OutputReceiver(
        address indexed mintTo,
        address indexed token,
        uint256 tokenId,
        uint256 amountTokens,
        uint256 indexed fnftId,
        bytes extraData
    );

    event WithdrawERC20OutputReceiver(
        address indexed caller, address indexed token, uint256 amountTokens, uint256 indexed fnftId, bytes extraData
    );

    event WithdrawERC721OutputReceiver(
        address indexed caller, address indexed token, uint256[] tokenIds, uint256 indexed fnftId, bytes extraData
    );

    event WithdrawERC1155OutputReceiver(
        address indexed caller,
        address indexed token,
        uint256 tokenId,
        uint256 amountTokens,
        uint256 indexed fnftId,
        bytes extraData
    );

    event TransferERC20OutputReceiver(
        address indexed transferTo,
        address indexed transferFrom,
        address indexed token,
        uint256 amountTokens,
        uint256 fnftId,
        bytes extraData
    );

    event TransferERC721OutputReceiver(
        address indexed transferTo,
        address indexed transferFrom,
        address indexed token,
        uint256[] tokenIds,
        uint256 fnftId,
        bytes extraData
    );

    event TransferERC1155OutputReceiver(
        address indexed transferTo,
        address indexed transferFrom,
        address indexed token,
        uint256 tokenId,
        uint256 amountTokens,
        uint256 fnftId,
        bytes extraData
    );

    function receiveRevestOutput(uint256 fnftId, address asset, address payable owner, uint256 quantity) external;

    function getCustomMetadata(uint256 fnftId) external view returns (string memory);

    function getValue(uint256 fnftId) external view returns (uint256);

    function getAsset(uint256 fnftId) external view returns (address);

    function getOutputDisplayValues(uint256 fnftId) external view returns (bytes memory);

    function handleTimelockExtensions(uint256 fnftId, uint256 expiration, address caller) external;

    function handleAdditionalDeposit(uint256 fnftId, uint256 amount, uint256 quantity, address caller) external;

    function onTransferFNFT(
        uint256 fnftId,
        address operator,
        address from,
        address to,
        uint256 quantity,
        bytes memory data
    ) external;
}
