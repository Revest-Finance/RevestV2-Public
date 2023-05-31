// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Revest_721.sol";
import "src/TokenVault.sol";
import "src/LockManager.sol";
import "src/FNFTHandler.sol";
import "./ExampleAddressLock.sol";

import "src/lib/PermitHash.sol";
import "src/interfaces/IAllowanceTransfer.sol";
import "src/lib/EIP712.sol";

import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Revest721Tests is Test {
    using PermitHash for IAllowanceTransfer.PermitBatch;
    using SafeTransferLib for ERC20;

    Revest_721 public immutable revest;
    TokenVault public immutable vault;
    LockManager public immutable lockManager;
    FNFTHandler public immutable fnftHandler;
    ExampleAddressLock public immutable addressLock;

    uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY"); //Useful for EIP-712 Testing
    address alice = vm.rememberKey(PRIVATE_KEY);
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IERC721 boredApe = IERC721(0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D);

    constructor() {
        vault = new TokenVault();
        revest = new Revest_721(address(WETH), address(vault));
        lockManager = new LockManager(address(WETH));
        fnftHandler = new FNFTHandler(address(0));
        addressLock = new ExampleAddressLock();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(address(revest), "revest");
        vm.label(address(vault), "tokenVault");
        vm.label(address(fnftHandler), "fnftHandler");
        vm.label(address(lockManager), "lockManager");
        vm.label(address(addressLock), "addressLock");
        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");

        deal(address(WETH), alice, type(uint256).max);
        deal(address(USDC), alice, type(uint256).max);

        fnftHandler.transferOwnership(address(revest)); //Transfer ownership to Revest from deployer

        startHoax(alice, alice);
        USDC.safeApprove(address(revest), type(uint256).max);
        USDC.safeApprove(PERMIT2, type(uint256).max);

        WETH.safeApprove(address(revest), type(uint256).max);
        WETH.safeApprove(PERMIT2, type(uint256).max);

        address tempOwner = IERC721(boredApe).ownerOf(1);
        changePrank(tempOwner);
        boredApe.transferFrom(tempOwner, alice, 1);
    }

    function setUp() public {}

    function testMintTimeLockToNFT(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e12);

        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        uint256 tokenId = 1;
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: tokenId,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        uint256 nonce = revest.numfnfts(address(boredApe), 1);

        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        address walletAddr = revest.getAddressForFNFT(salt);
        console.log("smart wallet in test: %s", walletAddr);

        //Check Minting was successful
        {
            //Funds were deducted from alice
            uint256 postBal = USDC.balanceOf(alice);
            console.log("Alice Pre Bal: ", preBal);
            console.log("Alice Post Bal: ", postBal);
            assertEq(postBal, preBal - amount, "balance did not decrease by expected amount");

            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

            //Lock was created
            ILockManager.Lock memory lock = lockManager.getLock(lockId);
            assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.TimeLock), "lock type is not TimeLock");
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);

            config = revest.getFNFT(salt);
            assertEq(config.depositAmount, amount, "deposit amount is not expected value");
            assertEq(config.asset, address(USDC), "asset is not expected value");
            assertEq(config.nonce, nonce, "nonce is not expected value");
        }

        //Transfer the FNFT from Alice -> Bob
        boredApe.transferFrom(alice, bob, tokenId);

        changePrank(bob);
        vm.expectRevert(bytes("E006"));
        revest.withdrawFNFT(salt, 1);

        skip(1 weeks);
        revest.withdrawFNFT(salt, 1);
        assertEq(USDC.balanceOf(bob), amount, "bob did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet
        assertEq(lockManager.getLock(lockId).unlocked, true, "lock was not unlocked");
    }

    function testMintAddressLockToNFT(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e14);
        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint256 id = 1;
        uint256 nonce = revest.numfnfts(address(boredApe), id);

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: nonce,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintAddressLock(
            address(addressLock), //Set carol as the unlocker
            "",
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        ILockManager.Lock memory lock = lockManager.getLock(lockId);
        assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.AddressLock), "lock type is not AddressLock");
        assertEq(lock.unlocked, false);
        assertEq(lock.addressLock, address(addressLock), "address lock is not expected value");
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        config = revest.getFNFT(salt);
        assertEq(config.nonce, nonce, "nonce is not expected value");
        assertEq(revest.numfnfts(address(boredApe), id), nonce + 1, "nonce was not incremented");

        vm.expectRevert(bytes("E021"));
        revest.withdrawFNFT(salt, 1); //Should revert because carol has not approved it yet

        //Have Carol unlock the FNFT
        if (block.timestamp % 2 != 0) skip(1 seconds);

        //Change back to Alice and have her withdraw the FNFT
        revest.withdrawFNFT(salt, 1);

        skip(1 seconds);

        //Check that the lock was unlocked and all funds returned to alice
        assertEq(USDC.balanceOf(alice), preBal, "bob did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet
        assertEq(lockManager.getLock(lockId).unlocked, true, "lock was not unlocked");
    }

    function testProxyCall(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e20);

        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        uint256 tokenId = 1;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: tokenId,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        uint256 nonce = revest.numfnfts(address(boredApe), 1);

        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        address walletAddr = revest.getAddressForFNFT(salt);

        //Check Minting was successful
        {
            //Funds were deducted from alice
            uint256 postBal = USDC.balanceOf(alice);
            console.log("Alice Pre Bal: ", preBal);
            console.log("Alice Post Bal: ", postBal);
            assertEq(postBal, preBal - amount, "balance did not decrease by expected amount");

            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

            //Lock was created
            ILockManager.Lock memory lock = lockManager.getLock(lockId);
            assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.TimeLock), "lock type is not TimeLock");
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);

            config = revest.getFNFT(salt);
            assertEq(config.depositAmount, amount, "deposit amount is not expected value");
            assertEq(config.asset, address(USDC), "asset is not expected value");
            assertEq(config.nonce, nonce, "nonce is not expected value");
        }

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(USDC);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(USDC.transfer.selector, alice, amount);

        //Do a proxy call with a blacklisted function selector
        vm.expectRevert(bytes("E024"));
        revest.proxyCall(salt, targets, values, calldatas);

        //Perform a state changing proxy call that is allowed
        deal(address(WETH), walletAddr, 10 ether);
        targets[0] = address(WETH);
        calldatas[0] = abi.encodeWithSelector(WETH.transfer.selector, alice, 1 ether);
        revest.proxyCall(salt, targets, values, calldatas);

        //Prevent Create2 Error from Foundry semantic
        destroyAccount(walletAddr, address(this));

        //Now do one with a whitelisted selector. It should succeed.
        targets[0] = address(USDC);
        calldatas[0] = abi.encodeWithSelector(USDC.balanceOf.selector, walletAddr);
        bytes[] memory returnData = revest.proxyCall(salt, targets, values, calldatas);
        assertEq(returnData.length, 1, "return data length is not expected value");
        assertEq(abi.decode(returnData[0], (uint256)), USDC.balanceOf(walletAddr), "return data is not expected value");

        //Should fail because Bob is not the canonical owner of the NFT
        changePrank(bob);
        vm.expectRevert(bytes("E023"));
        revest.proxyCall(salt, targets, values, calldatas);
    }

    function testMultipleFNFTsToOneNFT(uint256 amount, uint256 wethAmount) public {
        vm.assume(amount >= 1e6 && amount <= 1e14);
        vm.assume(wethAmount >= 1e18 && wethAmount <= 1e36);

        startHoax(alice, alice);

        uint256 preBalUSDC = USDC.balanceOf(bob);
        uint256 preBalWETH = WETH.balanceOf(bob);

        // uint256 tokenId = 1;
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 1,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        bytes32 salt1;
        bytes32 salt2;

        {
            uint256 nonce1;
            uint256 nonce2;
            bytes32 lockId1;
            bytes32 lockId2;

            nonce1 = revest.numfnfts(address(boredApe), 1);
            (salt1, lockId1) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

            config.asset = address(WETH);
            config.depositAmount = wethAmount;

            nonce2 = revest.numfnfts(address(boredApe), 1);
            (salt2, lockId2) = revest.mintTimeLock(block.timestamp + 2 weeks, recipients, amounts, config);
        }

        {
            address walletAddr = revest.getAddressForFNFT(salt1);
            address walletAddr2 = revest.getAddressForFNFT(salt2);
            assertEq(walletAddr, walletAddr2, "wallet addresses are not equal");

            assertEq(
                WETH.balanceOf(walletAddr), wethAmount, "wallet balance did not increase by expected amount of WETH"
            );
            assertEq(USDC.balanceOf(walletAddr), amount, "wallet balance did not increase by expected amount of USDC");

            assertEq(revest.numfnfts(address(boredApe), 1), 2);

            skip(2 weeks);
            boredApe.transferFrom(alice, bob, 1);
            changePrank(alice); //Should fail because alice does not have the NFT anymore
            vm.expectRevert(bytes("E023"));
            revest.withdrawFNFT(salt1, 1);

            changePrank(bob); //Should succeed because Bob has the NFT
            revest.withdrawFNFT(salt1, 1);

            //Prevent Create2 Error from Foundry semantic
            destroyAccount(walletAddr, address(this));

            revest.withdrawFNFT(salt2, 1);

            //She should get the funds back
            assertEq(USDC.balanceOf(bob), preBalUSDC + amount, "alice balance did not increase by expected amount");
            assertEq(WETH.balanceOf(bob), preBalWETH + wethAmount, "alice balance did not increase by expected amount");
        }
    }
}
