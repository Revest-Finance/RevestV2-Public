// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Revest_721.sol";
import "src/TokenVault.sol";
import "src/LockManager_Timelock.sol";
import "src/LockManager_Addresslock.sol";

import "src/FNFTHandler.sol";
import "src/MetadataHandler.sol";

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

    LockManager_Timelock public immutable lockManager_timelock;
    LockManager_Addresslock public immutable lockManager_addresslock;

    MetadataHandler public immutable metadataHandler;

    uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY"); //Useful for EIP-712 Testing
    address alice = vm.rememberKey(PRIVATE_KEY);
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IERC721 boredApe = IERC721(0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D);

    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint32 nonce;

    bytes signature;
    IAllowanceTransfer.PermitBatch permit;

    string baseURI = "https://ipfs.io/ipfs/";

    address public constant govController = address(0xdead);

    constructor() {
        vault = new TokenVault();
        metadataHandler = new MetadataHandler(baseURI);
        revest = new Revest_721(address(WETH), address(vault), address(metadataHandler), govController);

        lockManager_timelock = new LockManager_Timelock(address(WETH));
        lockManager_addresslock = new LockManager_Addresslock(address(WETH));

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(address(revest), "revest");
        vm.label(address(vault), "tokenVault");

        vm.label(address(lockManager_timelock), "lockManager_timelock");
        vm.label(address(lockManager_addresslock), "lockManager_addresslock");

        vm.label(address(USDC), "USDC");
        vm.label(address(WETH), "WETH");

        deal(address(WETH), alice, type(uint256).max);
        deal(address(USDC), alice, type(uint256).max);
        deal(alice, type(uint256).max);

        startHoax(alice, alice);
        USDC.safeApprove(address(revest), type(uint256).max);
        USDC.safeApprove(PERMIT2, type(uint256).max);

        WETH.safeApprove(address(revest), type(uint256).max);
        WETH.safeApprove(PERMIT2, type(uint256).max);

        address tempOwner = IERC721(boredApe).ownerOf(1);
        changePrank(tempOwner);
        boredApe.transferFrom(tempOwner, alice, 1);
    }

    function setUp() public {
        nonce = revest.numfnfts(address(boredApe), 1);

        // --- CALCULATING THE SIGNATURE FOR PERMIT2 AHEAD OF TIME PREVENTS STACK TOO DEEP --- DO NOT REMOVE
        IAllowanceTransfer.PermitDetails memory details = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: type(uint160).max,
            expiration: 0, //Only valid for length of the tx
            nonce: uint48(0)
        });

        permit.spender = address(revest);
        permit.sigDeadline = block.timestamp + 1 weeks;
        permit.details.push(details);

        {
            bytes32 DOMAIN_SEPARATOR = EIP712(PERMIT2).DOMAIN_SEPARATOR();
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, permit.hash()));

            //Sign the permit info
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);
            signature = abi.encodePacked(r, s, v);
        }
    }

    function testMintTimeLockToNFT(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e12);

        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        uint88 tokenId = 1;
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: nonce,
            fnftId: tokenId,
            maturityExtension: false
        });

        config.handler = address(0);
        vm.expectRevert(bytes("E001"));
        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        config.handler = address(boredApe);
        (uint id, bytes32 lockId) =
            revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(id);

        assertEq(revest.getSaltFromId(address(boredApe), 1, 0), id, "salt is not expected value");

        //Check Minting was successful
        {
            //Funds were deducted from alice
            uint256 postBal = USDC.balanceOf(alice);
            assertEq(postBal, preBal - amount, "balance did not decrease by expected amount");

            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

            //Lock was created
            ILockManager.Lock memory lock = lockManager_timelock.getLock(lockId);
            assertEq(
                uint256(lockManager_timelock.lockType()),
                uint256(ILockManager.LockType.TimeLock),
                "lock type is not TimeLock"
            );
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);

            config = revest.getFNFT(id);
            assertEq(revest.getValue(id), amount, "deposit amount is not expected value");
            assertEq(config.asset, address(USDC), "asset is not expected value");
            assertEq(config.nonce, nonce, "nonce is not expected value");
        }

        //Transfer the FNFT from Alice -> Bob
        boredApe.transferFrom(alice, bob, tokenId);

        changePrank(bob);
        vm.expectRevert(bytes("E006"));
        revest.withdrawFNFT(id, 1);

        skip(1 weeks);
        revest.withdrawFNFT(id, 1);
        assertEq(USDC.balanceOf(bob), amount, "bob did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet
        assertEq(lockManager_timelock.getLock(lockId).unlocked, true, "lock was not unlocked");
    }

    function testMintAddressLockToNFT(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e14);
        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_addresslock),
            nonce: nonce,
            fnftId: 1,
            maturityExtension: false
        });

        config.handler = address(0);
        vm.expectRevert(bytes("E001"));
        revest.mintAddressLock("", recipients, amounts, amount, config);

        config.handler = address(boredApe);

        (uint id, bytes32 lockId) = revest.mintAddressLock("", recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(id);

        //Lock was created
        ILockManager.Lock memory lock = lockManager_addresslock.getLock(lockId);
        assertEq(
            uint256(lockManager_addresslock.lockType()),
            uint256(ILockManager.LockType.AddressLock),
            "lock type is not AddressLock"
        );
        assertEq(lock.unlocked, false);
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        config = revest.getFNFT(id);
        assertEq(config.nonce, nonce, "nonce is not expected value");

        assertEq(revest.numfnfts(address(boredApe), 1), nonce + 1, "nonce was not incremented");

        vm.expectRevert(bytes("E006"));
        revest.withdrawFNFT(id, 1); //Should revert because carol has not approved it yet

        //Have Carol unlock the FNFT
        if (block.timestamp % 2 != 0) skip(1 seconds);

        //Change back to Alice and have her withdraw the FNFT
        revest.withdrawFNFT(id, 1);

        skip(1 seconds);

        //Check that the lock was unlocked and all funds returned to alice
        assertEq(USDC.balanceOf(alice), preBal, "bob did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet
        assertEq(lockManager_addresslock.getLock(lockId).unlocked, true, "lock was not unlocked");
    }

    function testProxyCall(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e20);

        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        uint88 tokenId = 1;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: tokenId,
            maturityExtension: false
        });

        (uint id, bytes32 lockId) =
            revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(id);
        console.log("walletAddr: %s", walletAddr);

        //Check Minting was successful
        {
            //Funds were deducted from alice
            uint256 postBal = USDC.balanceOf(alice);
            assertEq(postBal, preBal - amount, "balance did not decrease by expected amount");

            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

            //Lock was created
            ILockManager.Lock memory lock = lockManager_timelock.getLock(lockId);
            assertEq(
                uint256(lockManager_timelock.lockType()),
                uint256(ILockManager.LockType.TimeLock),
                "lock type is not TimeLock"
            );
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);

            config = revest.getFNFT(id);
            assertEq(revest.getValue(id), amount, "deposit amount is not expected value");
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
        vm.expectRevert(bytes("E013"));
        revest.proxyCall(id, targets, values, calldatas);

        console.log("---------------------------------------------");

        //Perform a state changing proxy call that is allowed
        deal(address(WETH), walletAddr, 10 ether);
        targets[0] = address(WETH);
        calldatas[0] = abi.encodeWithSelector(WETH.transfer.selector, alice, 1 ether);
        revest.proxyCall(id, targets, values, calldatas);

        //Prevent Create2 Error from Foundry semantic
        destroyAccount(walletAddr, address(this));

        //Now do one with a whitelisted selector. It should succeed.
        targets[0] = address(USDC);
        calldatas[0] = abi.encodeWithSelector(USDC.balanceOf.selector, walletAddr);
        bytes[] memory returnData = revest.proxyCall(id, targets, values, calldatas);
        assertEq(returnData.length, 1, "return data length is not expected value");
        assertEq(abi.decode(returnData[0], (uint256)), USDC.balanceOf(walletAddr), "return data is not expected value");

        //Should fail because Bob is not the canonical owner of the NFT
        changePrank(bob);
        vm.expectRevert(bytes("E023"));
        revest.proxyCall(id, targets, values, calldatas);

        changePrank(alice);
        values = new uint[](2);
        vm.expectRevert(bytes("E026"));
        revest.proxyCall(id, targets, values, calldatas);
    }

    function testMultipleFNFTsToOneNFT(uint256 amount, uint256 wethAmount) public {
        vm.assume(amount >= 1e6 && amount <= 1e14);
        vm.assume(wethAmount >= 1e18 && wethAmount <= 1e36);

        startHoax(alice, alice);

        uint256 preBalUSDC = USDC.balanceOf(bob);
        uint256 preBalWETH = WETH.balanceOf(bob);

        // uint88 tokenId = 1;
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = amount;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: 1,
            maturityExtension: false
        });

        uint salt1;
        uint salt2;

        {
            (salt1,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

            config.asset = address(WETH);

            (salt2,) = revest.mintTimeLock(block.timestamp + 2 weeks, recipients, amounts, wethAmount, config);
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

    function testDepositAdditionalToToFNFT(uint256 amount, uint256 additionalDepositAmount) public {
        vm.assume(amount >= 1e6 && amount <= 1e20);
        vm.assume(additionalDepositAmount >= 1e6 && additionalDepositAmount <= 1e20);

        startHoax(alice, alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 preBal = USDC.balanceOf(alice);

        uint256 supply = 1;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: nonce,
            fnftId: 1,
            maturityExtension: false
        });

        (uint id,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(id);
        uint256 balanceBefore = USDC.balanceOf(walletAddr);
        uint256 aliceBalanceBeforeAdditionalDeposit = USDC.balanceOf(alice);

        uint256 valueBeforeDestruction;
        {
            revest.depositAdditionalToFNFT(id, additionalDepositAmount);

            assertEq(
                USDC.balanceOf(walletAddr),
                balanceBefore + (additionalDepositAmount),
                "vault balance did not increase by expected amount"
            );
            assertEq(
                USDC.balanceOf(alice),
                aliceBalanceBeforeAdditionalDeposit - (additionalDepositAmount * supply),
                "alice balance did not decrease by expected amount"
            );

            assertEq(
                USDC.balanceOf(alice),
                preBal - (supply * (amount + additionalDepositAmount)),
                "alice balance did not decrease by expected amount"
            );

            assertEq(revest.getValue(id), amount + additionalDepositAmount, "deposit amount was not updated");

            valueBeforeDestruction = revest.getValue(id);

            skip(1 weeks);

            boredApe.transferFrom(alice, bob, 1);

            changePrank(bob);
            revest.withdrawFNFT(id, supply);
            destroyAccount(walletAddr, address(this));
            boredApe.transferFrom(bob, alice, 1);
        }

        assertEq(USDC.balanceOf(bob), valueBeforeDestruction, "bob balance did not increase by expected amount");

        assertEq(USDC.balanceOf(bob), supply * (amount + additionalDepositAmount), "full amount not transfered to bob");

        assertEq(
            USDC.balanceOf(alice), preBal - USDC.balanceOf(bob), "alice balance is not equal to original minus bob's"
        );

        changePrank(alice);
        preBal = alice.balance;

        uint256 wethPreBal = WETH.balanceOf(alice);
        (id,) = revest.mintTimeLock{value: 2 ether}(block.timestamp + 1 weeks, recipients, amounts, 2 ether, config);

        vm.expectRevert(bytes("E027"));
        revest.depositAdditionalToFNFT{value: 2 ether}(id, 1 ether);

        revest.depositAdditionalToFNFT{value: 1 ether}(id, 1 ether);
        revest.depositAdditionalToFNFT(id, 1 ether);

        assertEq(alice.balance, preBal - (2 ether + 1 ether), "alice balance did not decrease by expected amountof ETH");
        assertEq(
            WETH.balanceOf(alice), wethPreBal - 1 ether, "alice balance did not decrease by expected amount of WETH"
        );

        IController.FNFTConfig memory storedConfig = revest.getFNFT(id);
        assertEq(storedConfig.asset, ETH_ADDRESS, "asset was not set to ETH");
        assertEq(revest.getValue(id), 4 ether, "deposit amount was not set to amount");

        skip(1 weeks);

        revest.withdrawFNFT(id, 1);
        assertEq(alice.balance, preBal + 1 ether, "alice balance did not increase by expected amount of ETH");
    }

    function testmintTimeLockAndExtendMaturity(uint256 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e20);

        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: nonce,
            fnftId: 1,
            maturityExtension: true
        });

        (uint id, bytes32 lockId) =
            revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);
        address walletAddr;

        {
            walletAddr = revest.getAddressForFNFT(id);
            assertEq(USDC.balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

            boredApe.transferFrom(alice, bob, 1);

            vm.expectRevert(bytes("E023")); //Revert because you don't own the FNFT anymore
            revest.extendFNFTMaturity(id, block.timestamp + 1 weeks); //Extend a week beyond the current endDate

            //Send it back to Alice so she can extend maturity
            changePrank(bob);
            boredApe.transferFrom(bob, alice, 1);

            changePrank(alice);

            skip(2 weeks);

            vm.expectRevert(bytes("E015")); //Revert because the new FNFT maturity date is in the past
            revest.extendFNFTMaturity(id, block.timestamp - 2 weeks); //Extend a week beyond the current endDate

            vm.expectRevert(bytes("E007")); //Revert because previous FNFT maturity date has already passed
            revest.extendFNFTMaturity(id, block.timestamp + 2 weeks);

            rewind(2 weeks); //Go back 2 weeks to actually extend this time

            vm.expectRevert(bytes("E010"));
            revest.extendFNFTMaturity(id, block.timestamp + 1 weeks); //Extend a week beyond the current endDate

            revest.extendFNFTMaturity(id, block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            uint256 newEndTime = lockManager_timelock.getLock(lockId).timeLockExpiry;
            assertEq(newEndTime, block.timestamp + 2 weeks, "lock did not extend maturity by expected amount");

            skip(2 weeks);

            revest.withdrawFNFT(id, 1);

            assertEq(USDC.balanceOf(alice), preBal, "alice balance did not increase by expected amount");
        }

        //Same Test but should fail to extend maturity because maturityExtension is false
        config.maturityExtension = false;

        (id, lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        walletAddr = revest.getAddressForFNFT(id);
        assertEq(USDC.balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

        vm.expectRevert(bytes("E009")); //Revert because FNFT is marked as non-extendable
        revest.extendFNFTMaturity(id, block.timestamp + 2 weeks); //Extend a week beyond the current endDate
    }

    function testMintFNFTWithEth(uint256 amount) public {
        vm.assume(amount >= 1 ether && amount < 1000 ether);

        startHoax(alice, alice);

        uint256 preBal = alice.balance;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;


        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(boredApe),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: nonce,
            fnftId: 1,
            maturityExtension: false
        });

        (uint id,) =
            revest.mintTimeLock{value: amount}(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(id);
        assertEq(ERC20(WETH).balanceOf(walletAddr), amount, "vault balance did not increase by expected amount");

        assertEq(alice.balance, preBal - amount, "alice balance did not decrease by expected amountof ETH");

        IController.FNFTConfig memory storedConfig = revest.getFNFT(id);
        assertEq(storedConfig.asset, ETH_ADDRESS, "asset was not set to ETH");
        assertEq(revest.getValue(id), amount, "deposit amount was not set to amount");

        skip(1 weeks);
        revest.withdrawFNFT(id, 1);
        assertEq(alice.balance, preBal, "alice balance did not increase by expected amount of ETH");
    }

    function testMintFNFTWithPermit2(uint256 amount, uint256 additionalDepositAmount) public {
        // vm.assume(amount >= 1e6 && amount <= 1e12);
        amount = bound(amount, 1e6, 1e12);
        vm.assume(additionalDepositAmount >= 1e6 && additionalDepositAmount <= 1e12);

        startHoax(alice, alice);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint id;
        bytes32 lockId;
        {
            IController.FNFTConfig memory config = IController.FNFTConfig({
                handler: address(boredApe),
                asset: address(USDC),
                lockManager: address(lockManager_timelock),
                nonce: 0,
                fnftId: 1,
                maturityExtension: true
            });

            (id, lockId) = revest.mintTimeLockWithPermit(
                block.timestamp + 1 weeks, recipients, amounts, amount, config, permit, signature
            );
        }

        assertEq(USDC.balanceOf(revest.getAddressForFNFT(id)), amount, "USDC not deposited into vault");

        //Test that Lock was created
        ILockManager.Lock memory lock = lockManager_timelock.getLock(lockId);
        assertEq(
            uint256(lockManager_timelock.lockType()),
            uint256(ILockManager.LockType.TimeLock),
            "lock type is not TimeLock"
        );
        assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
        assertEq(lock.unlocked, false);

        address walletAddr = revest.getAddressForFNFT(id);
        uint256 balanceBefore = USDC.balanceOf(walletAddr);

        uint256 aliceBalanceBeforeAdditionalDeposit = USDC.balanceOf(alice);

        {
            permit.details[0].nonce++;
            bytes32 DOMAIN_SEPARATOR = EIP712(PERMIT2).DOMAIN_SEPARATOR();
            bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, permit.hash()));

            //Sign the permit info
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);
            signature = abi.encodePacked(r, s, v);
        }

        revest.depositAdditionalToFNFTWithPermit(id, additionalDepositAmount, permit, signature);

        {
            assertEq(
                USDC.balanceOf(walletAddr),
                balanceBefore + additionalDepositAmount,
                "vault balance did not increase by expected amount"
            );

            assertEq(
                USDC.balanceOf(alice),
                aliceBalanceBeforeAdditionalDeposit - additionalDepositAmount,
                "alice balance did not decrease by expected amount"
            );

            assertEq(
                USDC.balanceOf(alice),
                preBal - (amount + additionalDepositAmount),
                "alice balance did not decrease by expected amount"
            );

            assertEq(revest.getValue(id), amount + additionalDepositAmount, "deposit amount was not updated");
        }

        skip(1 weeks);
        revest.withdrawFNFT(id, 1);
        assertEq(USDC.balanceOf(alice), preBal, "alice balance did not increase by expected amount");
    }
}
