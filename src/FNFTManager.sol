// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

import "solmate/tokens/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./lib/FNFTRenderer.sol";

contract RevestNFTManager is ERC721 {
    address public immutable factory;
    uint256 private nextTokenId;
    uint256 public totalSupply;
    mapping(uint256 => AddressLock) public lockList;

    event AddAddressLock(
        uint fnftId,
        uint amount,
        address tokenAddress,
        address unlockAddress
    );

    struct AddressLock {
        uint tokenId; //TODO: added indexed 
        string assetName;
        string assetTicker;
        uint amount;
        address tokenAddress;
        address unlockAddress;
    }

    function mintAddressLock(
        uint amount, 
        address tokenAddress, 
        address unlockAddress
    ) public returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _mint(unlockAddress, tokenId);
        totalSupply++;

        string memory assetName = ERC20(tokenAddress).name();
        string memory assetTicker = ERC20(tokenAddress).symbol();


        AddressLock memory currentLock = AddressLock(tokenId, assetName, assetTicker, amount, tokenAddress, unlockAddress);
        lockList[tokenId] = currentLock;
        emit AddAddressLock(tokenId, amount, tokenAddress, unlockAddress);
    }

    constructor(address factoryAddress)
        ERC721("Revest FNFT Lock", "FNFT")
    {
        factory = factoryAddress;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        AddressLock memory addressLock = lockList[tokenId];

        //TODO: fix the return NFT 
        return
            FNFTRenderer.render(
                FNFTRenderer.RenderParams({
                    assetName: addressLock.assetName,
                    assetTicker: addressLock.assetTicker,
                    amount: addressLock.amount,
                    lockType: "address lock",
                    unlockAddress: addressLock.unlockAddress
                })
            );
    }
}