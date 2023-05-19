// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Test, stdError} from "forge-std/Test.sol";

import "../src/FNFTManager.sol";
import "../src/Revest.sol";
import "./ERC20Mintable.sol";



contract FNFTManagerTest is Test{
    ERC20Mintable weth;
    ERC20Mintable usdc;
    ERC20Mintable dai;
    ERC20Mintable rvst;
    FNFTManager nft;


    function setUp() public {
        usdc = new ERC20Mintable("USDC", "USDC", 18);
        weth = new ERC20Mintable("Ether", "WETH", 18);
        dai = new ERC20Mintable("DAI", "DAI", 18);
        rvst = new ERC20Mintable("Revest", "RVST", 18);

        factory = new Revest('0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78',"0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
        nft = FNFTManager(address(factory))

    }

    // function testMint() {

    // }

    function printOutTokenURI() {
        
    }


}