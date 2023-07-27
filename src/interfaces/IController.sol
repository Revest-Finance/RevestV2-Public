// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

import "./ILockManager.sol";

interface IController {
    event FNFTWithdrawn(address indexed from, uint256 indexed fnftId, uint256 indexed quantity);
    event FNFTUnlocked(address indexed from, uint256 indexed fnftId);

    event DepositERC20(
        address indexed token, address indexed user, uint256 indexed fnftId, uint256 tokenAmount, address smartWallet
    );

    event WithdrawERC20(
        address indexed token, address indexed user, uint256 indexed fnftId, uint256 tokenAmount, address smartWallet
    );

    event CreateFNFT(uint256 indexed fnftId, address indexed from);
    event RedeemFNFT(uint256 indexed fnftId, address indexed from);

    struct FNFTConfig {
        //20 + 4 + 1 = 25 bytes -> 1 slot
        address asset; // The token being stored
        uint32 nonce;
        //20 + 1 + 11 = 32 bytes -> 1 slot
        address lockManager;
        bool maturityExtension; // Maturity extensions remaining
        
        //A storage slot can be saved by reducing this to a uint88 and casting when needed
        // uint256 fnftId; //type(uint88).max = 3.1e23

        //2 Slots but only Used by the Revest-721 -> Are left empty at the end for 1155 to save ~40k gas
        address handler;
    }

    //Used for stackTooDeep - Only kept in memory, efficient packing not needed
    struct MintParameters {
        uint256 endTime;
        address[] recipients;
        uint256[] quantities;
        uint256 depositAmount;
        uint fnftId;
        FNFTConfig fnftConfig;
        bool usePermit2;
    }

    function withdrawFNFT(uint fnftId, uint256 quantity) external;
    function unlockFNFT(uint fnftId) external;

    //View Functions
    function getValue(uint fnftId) external view returns (uint256);
    function getAsset(uint fnftId) external view returns (address);
    function getFNFT(uint salt) external view returns (FNFTConfig memory);
    function getLock(uint fnftId) external view returns (ILockManager.Lock memory);

    //Metadata Functions
    function getTokenURI(uint fnftId) external view returns (string memory);
    function renderTokenURI(uint tokenId, address owner)
        external
        view
        returns (string memory baseRenderURI, string[] memory parameters);

    function implementSmartWalletWithdrawal(bytes calldata data) external;

    //They're public variables in Revest_base but its useful to define it in the interface also
    function numfnfts(address, uint256) external view returns (uint32);
}
