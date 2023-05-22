// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Test, stdError} from "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../src/FNFTManager.sol";
import "../src/lib/FNFTRenderer.sol";
import "../src/Revest.sol";
import "./ERC20Mintable.sol";



contract FNFTManagerTest is Test{
    ERC20Mintable weth;
    ERC20Mintable usdc;
    ERC20Mintable dai;
    ERC20Mintable rvst;
    IRevest factory;
    FNFTManager public nft;


    function setUp() public {
        usdc = new ERC20Mintable("USDC", "USDC", 18);
        weth = new ERC20Mintable("Ether", "WETH", 18);
        dai = new ERC20Mintable("DAI", "DAI", 18);
        rvst = new ERC20Mintable("Revest", "RVST", 18);

        factory = new Revest(0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        nft = new FNFTManager(0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78);
        console2.log(address(nft));

        weth.mint(address(this), 10_000 ether);
        weth.approve(address(nft), type(uint256).max);
    }

    function testMint() public {
        uint256 tokenId = nft.mintAddressLock(10000000, 0x6982508145454Ce325dDbE47a25d4ec3d2311933, 0x4A54e0624A893915a767401413759f578C40ab3b);
        string memory tokenuri = nft.tokenURI(tokenId);

        console2.logString(tokenuri);
        
        assert(true);
    }

    function testFNFTRenderer() public {
        assertTokenURI(nft.displayRenderContent("Revest", "RVST", 100000, "address lock", address(bytes20(bytes('0xd2c6eB7527Ab1E188638B86F2c14bbAd5A431d78')))), "tokenuri0", "invalid token URI");
        //assert(true);
    }




    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////

    function assertTokenURI (
        string memory actual,
        string memory expectedFixture,
        string memory errMessage
    ) internal {
        string memory expected = vm.readFile(
            string.concat("./test/fixture/", expectedFixture)
        );

        assertEq(actual, string(expected), errMessage);
    }
}