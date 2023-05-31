// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.12;

interface IController {
    event FNFTWithdrawn(address indexed from, uint256 indexed fnftId, uint256 indexed quantity);

    event FNFTUnlocked(address indexed from, uint256 indexed fnftId);

    event DepositERC20(
        address indexed token, address indexed user, uint256 indexed fnftId, uint256 tokenAmount, address smartWallet
    );

    event WithdrawERC20(
        address indexed token, address indexed user, uint256 indexed fnftId, uint256 tokenAmount, address smartWallet
    );

    event CreateFNFT(bytes32 salt, uint256 indexed fnftId, address indexed from);

    event RedeemFNFT(bytes32 indexed salt, uint256 indexed fnftId, address indexed from);

    struct FNFTConfig {
        address pipeToContract; // Indicates if FNFT will pipe to another contract
        address handler;
        address asset; // The token being stored
        address lockManager;
        uint256 depositAmount; // The amount of each token being stored
        uint256 nonce; // The FNFT number
        uint256 quantity; // How many FNFTs
        uint256 fnftId; //the ID of the NFT the FNFT was minted to
        bytes32 lockId; // The salt used to generate the lock info
        bool maturityExtension; // Maturity extensions remaining
        bool useETH;
        bool nontransferrable;
    }

    //Used for stackTooDeep - TODO: See about removing this
    struct MintParameters {
        uint256 endTime;
        address[] recipients;
        uint256[] quantities;
        FNFTConfig fnftConfig;
        bool usePermit2;
    }

    function withdrawFNFT(bytes32 salt, uint256 quantity) external;
    function unlockFNFT(bytes32 salt) external;

    //View Functions
    function getValue(bytes32 fnftId) external view returns (uint256);
    function getAsset(bytes32 fnftId) external view returns (address);
    function getFNFT(bytes32 salt) external view returns (FNFTConfig memory);

    //Metadata Functions
    function getTokenURI(uint256 fnftId) external view returns (string memory);
    function renderTokenURI(uint256 tokenId, address owner)
        external
        view
        returns (string memory baseRenderURI, string[] memory parameters);

    //They're public variables in Revest_base but its useful to define it in the interface also
    function numfnfts(address, uint256) external view returns (uint256);
    function blacklistedFunctions(bytes4) external view returns (bool);
}
