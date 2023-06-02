// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "src/Revest_1155.sol";
import "src/TokenVault.sol";
import "src/LockManager.sol";
import "src/FNFTHandler.sol";
import "src/MetadataHandler.sol";
import "./ExampleAddressLock.sol";

import "src/lib/PermitHash.sol";
import "src/interfaces/IAllowanceTransfer.sol";
import "src/lib/EIP712.sol";

import "@solmate/utils/SafeTransferLib.sol";

contract Revest1155Tests is Test {
    using PermitHash for IAllowanceTransfer.PermitBatch;
    using SafeTransferLib for ERC20;

    Revest_1155 public immutable revest;
    TokenVault public immutable vault;
    LockManager public immutable lockManager;
    FNFTHandler public immutable fnftHandler;
    ExampleAddressLock public immutable addressLock;
    MetadataHandler public immutable metadataHandler;

    uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY"); //Useful for EIP-712 Testing
    address alice = vm.rememberKey(PRIVATE_KEY);
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes signature;
    IAllowanceTransfer.PermitBatch permit;

    string baseURI = "https://ipfs.io/ipfs/";

    constructor() {
        vault = new TokenVault();
        metadataHandler = new MetadataHandler(baseURI);
        revest = new Revest_1155(address(WETH), address(vault), address(metadataHandler));
        lockManager = new LockManager(address(WETH));
        fnftHandler = new FNFTHandler();
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
        deal(alice, 1000 ether);

        fnftHandler.transferOwnership(address(revest)); //Transfer ownership to Revest from deployer

        startHoax(alice, alice);

        USDC.safeApprove(address(revest), type(uint256).max);
        USDC.safeApprove(PERMIT2, type(uint256).max);

        WETH.safeApprove(address(revest), type(uint256).max);
        WETH.safeApprove(PERMIT2, type(uint256).max);
    }

    function setUp() public {
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

    function testMintTimeLockToAlice(uint8 supply, uint256 amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6 && amount < 1e12);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory supplies = new uint[](1);
        supplies[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        config.handler = address(0);
        vm.expectRevert(bytes("E001"));
        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, supplies, config);

        config.handler = address(fnftHandler);

        uint256 currentTime = block.timestamp;
        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, supplies, config);

        address walletAddr = revest.getAddressForFNFT(salt);

        //Check Minting was successful
        {
            //Funds were deducted from alice
            uint256 postBal = USDC.balanceOf(alice);

            assertEq(postBal, preBal - (supply * amount), "balance did not decrease by expected amount");

            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), supply * amount, "vault balance did not increase by expected amount");

            //FNFTs were minted to alice
            assertEq(fnftHandler.balanceOf(alice, id), supply, "alice did not receive expected amount of FNFTs");
            assertEq(fnftHandler.totalSupply(id), supply, "total supply of FNFTs did not increase by expected amount");

            //Lock was created
            ILockManager.Lock memory lock = lockManager.getLock(lockId);
            assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.TimeLock), "lock type is not TimeLock");

            assertFalse(lock.timeLockExpiry == 0, "timeLock Expiry should not be zero");
            assertEq(currentTime + 1 weeks, lock.timeLockExpiry, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);
        }

        //Transfer the FNFT from Alice -> Bob
        {
            fnftHandler.safeTransferFrom(alice, bob, id, supply, "");
            assertEq(fnftHandler.balanceOf(alice, id), 0, "alice did not lose expected amount of FNFTs");
            assertEq(fnftHandler.balanceOf(bob, id), supply, "bob did not receive expected amount of FNFTs");
        }

        changePrank(bob);
        vm.expectRevert(bytes("E006"));
        revest.unlockFNFT(salt);

        console.log("first maturity check");
        assertFalse(lockManager.getLockMaturity(lockId, id));

        skip(1 weeks + 1 seconds);
        console.log("second maturity check");
        assertFalse(!lockManager.getLockMaturity(lockId, id));

        revest.unlockFNFT(salt);
        revest.withdrawFNFT(salt, supply);

        assertEq(fnftHandler.balanceOf(bob, id), 0, "bob did not lose expected amount of FNFTs"); //All FNFTs were burned
        assertEq(USDC.balanceOf(bob), supply * amount, "bob did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount"); //Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet

        assertEq(revest.fnftIdToRevestId(address(fnftHandler), id), salt, "revestId was not set correctly");

        assertEq(revest.getAsset(salt), address(USDC), "asset was not set correctly");
        assertEq(revest.getValue(salt), amount, "value was not set correctly");

        //Test misc. branch for invalid lock type
        ILockManager.LockParam memory invalidLock;
        invalidLock.addressLock = address(addressLock);

        vm.expectRevert(bytes("E017"));
        ILockManager(address(lockManager)).createLock(salt, invalidLock);
    }

    function testBatchMintTimeLock(uint8 supply, uint256 amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6 && amount <= 1e12);

        uint256 preBal = USDC.balanceOf(alice);

        //Mint half to bob and half to alice
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory amounts = new uint[](2);
        amounts[0] = supply / 2;
        amounts[1] = supply / 2;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        config.handler = address(0);
        vm.expectRevert(bytes("E001"));
        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        config.handler = address(fnftHandler);

        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        address walletAddr = revest.getAddressForFNFT(salt);

        {
            //Funds were deducted from alice
            uint256 postBal = USDC.balanceOf(alice);
            assertEq(postBal, preBal - (supply * amount), "balance did not decrease by expected amount");

            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), supply * amount, "vault balance did not increase by expected amount");

            //FNFTs were minted to alice and Bob
            assertEq(fnftHandler.balanceOf(alice, id), supply / 2, "alice did not receive expected amount of FNFTs");
            assertEq(fnftHandler.balanceOf(bob, id), supply / 2, "alice did not receive expected amount of FNFTs");
            assertEq(fnftHandler.totalSupply(id), supply, "total supply of FNFTs did not increase by expected amount");

            //Lock was created
            ILockManager.Lock memory lock = lockManager.getLock(lockId);
            assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.TimeLock), "lock type is not TimeLock");
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);
        }

        vm.expectRevert("ERC1155: burn amount exceeds balance");
        revest.withdrawFNFT(salt, supply); //Should Revert for trying to burn more than balance

        vm.expectRevert(bytes("E006"));
        revest.withdrawFNFT(salt, supply / 2); //Should revert because lock is not expired

        vm.expectRevert(bytes("E003"));
        revest.withdrawFNFT(bytes32("0xdead"), supply / 2); //Should revert because lock is not expired

        skip(1 weeks);

        revest.withdrawFNFT(salt, supply / 2); //Should execute correctly

        assertEq(
            USDC.balanceOf(alice), preBal - ((supply * amount) / 2), "alice did not receive expected amount of USDC"
        );
        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice did not receive expected amount of FNFTs");
        assertEq(fnftHandler.totalSupply(id), supply / 2, "total supply of FNFTs did not decrease by expected amount");
        assertEq(USDC.balanceOf(walletAddr), (supply * amount) / 2, "vault balance did not decrease by expected amount");
        assertEq(
            fnftHandler.balanceOf(bob, id), fnftHandler.totalSupply(id), "expected and actual FNFT supply do not match"
        );
    }

    function testMintAddressLock(uint8 supply, uint256 amount) public {
        vm.assume(supply != 0);
        vm.assume(amount >= 1e6 && amount <= 1e12);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintAddressLock(address(addressLock), "", recipients, amounts, config);

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        ILockManager.Lock memory lock = lockManager.getLock(lockId);
        assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.AddressLock), "lock type is not AddressLock");
        assertEq(lock.unlocked, false);
        assertEq(lock.addressLock, address(addressLock), "address lock is not expected value");
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        if (block.timestamp % 2 == 0) skip(1 seconds);

        assertFalse(lockManager.getLockMaturity(lockId, id));

        vm.expectRevert(bytes("E021"));
        revest.withdrawFNFT(salt, supply); //Should revert because lock has not expired

        skip(1 seconds);
        assertFalse(!lockManager.getLockMaturity(lockId, id));
        revest.withdrawFNFT(salt, supply);

        //Check that the lock was unlocked and all funds returned to alice
        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice did not lose expected amount of FNFTs"); //All FNFTs were burned
        assertEq(USDC.balanceOf(alice), preBal, "alice did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount"); //Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet
    }

    function testDepositAdditionalToToFNFT(uint8 supply, uint256 amount, uint256 additionalDepositAmount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6 && amount <= 1e20);
        vm.assume(additionalDepositAmount >= 1e6 && additionalDepositAmount <= 1e20);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 preBal = USDC.balanceOf(alice);

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        address walletAddr = revest.getAddressForFNFT(salt);
        uint256 balanceBefore = USDC.balanceOf(walletAddr);
        uint256 aliceBalanceBeforeAdditionalDeposit = USDC.balanceOf(alice);

        uint256 tempSupply = supply / 2;
        {
            vm.expectRevert(bytes("E003"));
            revest.depositAdditionalToFNFT(bytes32("0xdead"), additionalDepositAmount);

            revest.depositAdditionalToFNFT(salt, additionalDepositAmount);
            assertEq(
                USDC.balanceOf(walletAddr),
                balanceBefore + additionalDepositAmount * supply,
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

            assertEq(
                revest.getFNFT(salt).depositAmount, amount + additionalDepositAmount, "deposit amount was not updated"
            );

            skip(1 weeks);

            fnftHandler.safeTransferFrom(alice, bob, id, tempSupply, "");

            changePrank(bob);
            revest.withdrawFNFT(salt, tempSupply);
            destroyAccount(walletAddr, address(this));
        }

        assertEq(
            USDC.balanceOf(bob),
            revest.getFNFT(salt).depositAmount * tempSupply,
            "alice balance did not increase by expected amount"
        );

        assertEq(
            USDC.balanceOf(bob), tempSupply * (amount + additionalDepositAmount), "full amount not transfered to bob"
        );

        changePrank(alice);
        revest.withdrawFNFT(salt, tempSupply);

        assertEq(
            USDC.balanceOf(alice), preBal - USDC.balanceOf(bob), "alice balance did not increase by expected amount"
        );
    }

    function testmintTimeLockAndExtendMaturity(uint8 supply, uint256 amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6 && amount <= 1e20);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);
        address walletAddr;

        {
            walletAddr = revest.getAddressForFNFT(salt);
            assertEq(USDC.balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount");

            fnftHandler.safeTransferFrom(alice, bob, id, 1, "");
            vm.expectRevert(bytes("E008")); //Revert because you don't own the entire supply of the FNFT
            revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            vm.expectRevert(bytes("E003")); //Revert because you don't own the entire supply of the FNFT
            revest.extendFNFTMaturity(bytes32("0xdead"), block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            //Send it back to Alice so she can extend maturity
            changePrank(bob);
            fnftHandler.safeTransferFrom(bob, alice, id, 1, "");

            changePrank(alice);

            skip(2 weeks);
            vm.expectRevert(bytes("E015")); //Revert because new FNFT maturity date has already passed
            revest.extendFNFTMaturity(salt, block.timestamp - 2 weeks); //Extend a week beyond the current endDate

            vm.expectRevert(bytes("E007")); //Revert because new FNFT maturity date has already passed
            revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            rewind(2 weeks); //Go back 2 weeks to actually extend this time

            uint256 currTime = block.timestamp;
            bytes32 newLockId = revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            uint256 newEndTime = lockManager.getLock(newLockId).timeLockExpiry;
            assertEq(newEndTime, currTime + 2 weeks, "lock did not extend maturity by expected amount");

            skip(2 weeks);
            revest.withdrawFNFT(salt, supply);

            assertEq(USDC.balanceOf(alice), preBal, "alice balance did not increase by expected amount");
        }

        //Same Test but should fail to extend maturity because maturityExtension is false
        config.maturityExtension = false;

        (salt, lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        walletAddr = revest.getAddressForFNFT(salt);
        assertEq(USDC.balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount");

        vm.expectRevert(bytes("E009")); //Revert because FNFT is marked as non-extendable
        revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate
    }

    function testMintFNFTWithEth(uint8 supply, uint256 amount) public {
        vm.assume(amount >= 1 ether && amount < 1000 ether);
        vm.assume(supply != 0);

        uint256 preBal = alice.balance;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(0),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: true,
            nontransferrable: false
        });

        (bytes32 salt,) =
            revest.mintTimeLock{value: amount * supply}(block.timestamp + 1 weeks, recipients, amounts, config);

        address walletAddr = revest.getAddressForFNFT(salt);
        assertEq(
            ERC20(WETH).balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount"
        );

        assertEq(alice.balance, preBal - (supply * amount), "alice balance did not decrease by expected amountof ETH");
        IController.FNFTConfig memory storedConfig = revest.getFNFT(salt);
        assertEq(storedConfig.useETH, true, "useETH was not set to true");
        assertEq(storedConfig.asset, address(0), "asset was not set to ETH");
        assertEq(storedConfig.depositAmount, amount, "deposit amount was not set to amount");

        skip(1 weeks);
        revest.withdrawFNFT(salt, supply);
        assertEq(alice.balance, preBal, "alice balance did not increase by expected amount of ETH");
    }

    function testCantTransferANonTransferrableFNFT() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: true
        });

        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        vm.expectRevert(bytes("E022")); //Revert because FNFT is marked as non-transferrable
        fnftHandler.safeTransferFrom(alice, bob, id, 1, "");

        fnftHandler.safeTransferFrom(alice, address(0xdead), id, 1, "");
        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice still owns FNFT");
        assertEq(fnftHandler.balanceOf(address(0xdead), id), 1, "alice still owns FNFT");
    }

    function testMintFNFTWithExistingTimeLock() public {
        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt1, bytes32 lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        config.lockId = lockId;

        (bytes32 salt2, bytes32 lockId2) = revest.mintTimeLock(block.timestamp + 3 weeks, recipients, amounts, config);

        assertEq(lockId, lockId2, "lockIds returned do not match");

        IController.FNFTConfig memory timelock1 = revest.getFNFT(salt1);
        IController.FNFTConfig memory timelock2 = revest.getFNFT(salt2);
        assertEq(timelock1.lockId, timelock2.lockId, "lockIds stored do not match");
        ILockManager.Lock memory lock = lockManager.getLock(lockId);

        assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock end date is not expected amount");
        skip(1 weeks);

        revest.withdrawFNFT(salt1, 1);

        bool unlocked = lockManager.getLockMaturity(lockId, id);
        assertEq(unlocked, true, "lock was not unlocked");
        revest.withdrawFNFT(salt2, 1);

        assertEq(USDC.balanceOf(alice), preBal, "alice did not receive expected amount of USDC");
    }

    function testMintFNFTWithExistingAddressLock() public {
        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt1, bytes32 lockId) = revest.mintAddressLock(address(addressLock), "", recipients, amounts, config);

        config.lockId = lockId;
        (bytes32 salt2, bytes32 lockId2) = revest.mintAddressLock(address(0), "", recipients, amounts, config);

        assertEq(lockId, lockId2, "lockIds returned do not match");

        IController.FNFTConfig memory timelock1 = revest.getFNFT(salt1);
        IController.FNFTConfig memory timelock2 = revest.getFNFT(salt2);
        assertEq(timelock1.lockId, timelock2.lockId, "lockIds stored do not match");

        ILockManager.Lock memory lock = lockManager.getLock(lockId);
        assertEq(lock.addressLock, address(addressLock), "expected and actual address lock does not match");

        if (block.timestamp % 2 != 0) skip(1 seconds);

        changePrank(alice);
        revest.withdrawFNFT(salt1, 1);

        bool unlocked = lockManager.getLockMaturity(lockId, id);
        assertEq(unlocked, true, "lock was not unlocked");
        revest.withdrawFNFT(salt2, 1);

        assertEq(USDC.balanceOf(alice), preBal, "alice did not receive expected amount of USDC");
    }

    function testTransferFNFTWithSignature() public {
        startHoax(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: false
        });

        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        bytes32 SET_APPROVALFORALL_TYPEHASH = keccak256(
            "transferFromWithPermit(address owner,address operator, bool approved, uint id, uint amount, uint256 deadline, uint nonce, bytes data)"
        );

        bytes32 DOMAIN_SEPARATOR = fnftHandler.DOMAIN_SEPARATOR();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        SET_APPROVALFORALL_TYPEHASH, alice, bob, true, id, 1, block.timestamp + 1 weeks, 0, bytes("")
                    )
                )
            )
        );

        //Sign the permit info
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);
        bytes memory transferSignature = abi.encodePacked(r, s, v);

        //The Permit info itself
        IFNFTHandler.permitApprovalInfo memory transferPermit = IFNFTHandler.permitApprovalInfo({
            owner: alice,
            operator: bob,
            id: id,
            amount: 1,
            deadline: block.timestamp + 1 weeks,
            data: bytes("")
        });

        skip(2 weeks);
        vm.expectRevert(bytes("ERC1155: signature expired"));
        fnftHandler.transferFromWithPermit(transferPermit, transferSignature);

        rewind(2 weeks);

        vm.expectRevert(bytes("E018"));
        fnftHandler.transferFromWithPermit(transferPermit, "0xdead");

        //Do the transfer
        fnftHandler.transferFromWithPermit(transferPermit, transferSignature);

        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice still owns FNFT");
        assertEq(fnftHandler.balanceOf(bob, id), 1, "bob does not own FNFT");
        assertEq(fnftHandler.isApprovedForAll(alice, bob), true);

        changePrank(revest.owner());

        Revest_1155 newRevest = new Revest_1155(address(WETH), address(vault), address(metadataHandler));

        revest.transferOwnershipFNFTHandler(address(newRevest), address(fnftHandler));
        assertEq(fnftHandler.owner(), address(newRevest), "handler ownership not transferred");

        changePrank(alice, alice);

        USDC.safeApprove(address(newRevest), type(uint256).max);

        id = fnftHandler.getNextId();
        newRevest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);
        assertEq(fnftHandler.balanceOf(alice, id), 1, "FNFT not minted to Alice");

        uint256[] memory transferAmounts = new uint[](1);
        uint256[] memory transferIds = new uint[](1);
        transferAmounts[0] = 0;
        transferIds[0] = id;
        vm.expectRevert(bytes("E020"));
        fnftHandler.safeBatchTransferFrom(alice, bob, transferIds, transferAmounts, "");
    }

    function testProxyCallFunctionality() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 2;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockId: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);

        address[] memory targets = new address[](1);
        targets[0] = address(USDC);
        uint256[] memory values = new uint[](1);
        bytes[] memory calldatas = new bytes[](1);

        //Blacklist transfer function
        changePrank(revest.owner());
        revest.changeSelectorVisibility(USDC.totalSupply.selector, true);
        changePrank(alice);

        //Transfer tokens out of the vault
        calldatas[0] = abi.encodeWithSelector(USDC.transfer.selector, bob, 1e6);

        //Expect Revert because invokes a blacklisted function
        vm.expectRevert(bytes("E013"));
        revest.proxyCall(salt, targets, values, calldatas);

        //Should succeed because valid proxy call to invoke
        calldatas[0] = abi.encodeWithSelector(USDC.totalSupply.selector);
        bytes[] memory returnDatas = revest.proxyCall(salt, targets, values, calldatas);

        assertEq(abi.decode(returnDatas[0], (uint256)), USDC.totalSupply(), "return data does not match expected value");

        fnftHandler.safeTransferFrom(alice, bob, id, 1, "");

        //Should revert because you no longer own the entire supply of the FNFT
        vm.expectRevert(bytes("E007"));
        revest.proxyCall(salt, targets, values, calldatas);

        skip(1 weeks);
        config.asset = address(0);
        config.useETH = true;
        config.depositAmount = 1 ether;
        targets[0] = address(WETH);
        (salt,) = revest.mintTimeLock{value: 1 ether}(block.timestamp + 1 weeks, recipients, amounts, config);
        calldatas[0] = abi.encodeWithSelector(IWETH.withdraw.selector, 1 ether);

        vm.expectRevert(bytes("E013"));
        revest.proxyCall(salt, targets, values, calldatas);

        vm.expectRevert(bytes("E025"));
        calldatas[0] = "0xdead";
        targets[0] = address(USDC);
        revest.proxyCall(salt, targets, values, calldatas);

        values = new uint[](2);
        vm.expectRevert(bytes("E026"));
        revest.proxyCall(salt, targets, values, calldatas);
    }

    function testMintTimeLockWithPermit2(uint160 amount) public {
        vm.assume(amount >= 1e6 && amount <= 1e12);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 id = fnftHandler.getNextId();

        bytes32 salt;
        bytes32 lockId;
        {
            IController.FNFTConfig memory config = IController.FNFTConfig({
                pipeToContract: address(0),
                handler: address(fnftHandler),
                asset: address(USDC),
                lockManager: address(lockManager),
                depositAmount: amount,
                nonce: 0,
                quantity: 0,
                fnftId: id,
                lockId: bytes32(0),
                maturityExtension: true,
                useETH: false,
                nontransferrable: true
            });

            vm.expectRevert(bytes("E024"));
            revest.mintTimeLockWithPermit(block.timestamp + 1 weeks, recipients, amounts, config, permit, "");

            (salt, lockId) =
                revest.mintTimeLockWithPermit(block.timestamp + 1 weeks, recipients, amounts, config, permit, signature);
        }

        assertEq(fnftHandler.balanceOf(alice, id), 1, "FNFT not minted");
        assertEq(USDC.balanceOf(revest.getAddressForFNFT(salt)), amount, "USDC not deposited into vault");

        //Test that Lock was created
        ILockManager.Lock memory lock = lockManager.getLock(lockId);
        assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.TimeLock), "lock type is not TimeLock");
        assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
        assertEq(lock.unlocked, false);
    }

    function testMintAddressLockWithPermit2(uint160 amount, uint8 supply) public {
        vm.assume(amount >= 1e6 && amount <= 1e12);
        vm.assume(supply >= 1);

        uint256 preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        vm.expectRevert(bytes("E024"));
        revest.mintAddressLockWithPermit(address(addressLock), "", recipients, amounts, config, permit, "");

        (bytes32 salt, bytes32 lockId) =
            revest.mintAddressLockWithPermit(address(addressLock), "", recipients, amounts, config, permit, signature);

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        ILockManager.Lock memory lock = lockManager.getLock(lockId);
        assertEq(uint256(lock.lockType), uint256(ILockManager.LockType.AddressLock), "lock type is not AddressLock");
        assertEq(lock.unlocked, false);
        assertEq(lock.addressLock, address(addressLock), "address lock is not expected value");
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        if (block.timestamp % 2 == 0) skip(1 seconds);

        vm.expectRevert(bytes("E021"));
        revest.withdrawFNFT(salt, supply); //Should revert because lock has not expired

        // console2.log("---SALT---");
        // console2.logBytes32(salt);

        skip(1 seconds);
        revest.withdrawFNFT(salt, supply);

        //Check that the lock was unlocked and all funds returned to alice
        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice did not lose expected amount of FNFTs"); //All FNFTs were burned
        assertEq(USDC.balanceOf(alice), preBal, "alice did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount"); //Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet
    }

    function testDepositAdditionalToToFNFTWithPermit2(uint8 supply, uint256 amount, uint256 additionalDepositAmount)
        public
    {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6 && amount <= 1e20);
        vm.assume(additionalDepositAmount >= 1e6 && additionalDepositAmount <= 1e20);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 preBal = USDC.balanceOf(alice);

        uint256 id = fnftHandler.getNextId();

        bytes32 salt;
        {
            IController.FNFTConfig memory config = IController.FNFTConfig({
                pipeToContract: address(0),
                handler: address(fnftHandler),
                asset: address(USDC),
                lockManager: address(lockManager),
                depositAmount: amount,
                nonce: 0,
                quantity: 0,
                fnftId: 0,
                lockId: bytes32(0),
                maturityExtension: false,
                useETH: false,
                nontransferrable: false
            });

            (salt,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, config);
        }

        address walletAddr = revest.getAddressForFNFT(salt);
        uint256 balanceBefore = USDC.balanceOf(walletAddr);
        uint256 aliceBalanceBeforeAdditionalDeposit = USDC.balanceOf(alice);

        vm.expectRevert(bytes("E024"));
        revest.depositAdditionalToFNFTWithPermit(salt, additionalDepositAmount, permit, "");

        revest.depositAdditionalToFNFTWithPermit(salt, additionalDepositAmount, permit, signature);

        {
            assertEq(
                USDC.balanceOf(walletAddr),
                balanceBefore + (additionalDepositAmount * supply),
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

            assertEq(
                revest.getFNFT(salt).depositAmount, amount + additionalDepositAmount, "deposit amount was not updated"
            );
        }

        uint256 tempSupply = supply / 2;
        skip(1 weeks);
        fnftHandler.safeTransferFrom(alice, bob, id, tempSupply, "");

        changePrank(bob);
        revest.withdrawFNFT(salt, tempSupply);
        destroyAccount(walletAddr, address(this));

        {
            assertEq(
                USDC.balanceOf(bob),
                revest.getFNFT(salt).depositAmount * tempSupply,
                "alice balance did not increase by expected amount"
            );

            assertEq(
                USDC.balanceOf(bob),
                tempSupply * (amount + additionalDepositAmount),
                "full amount not transfered to bob"
            );
        }

        changePrank(alice);
        revest.withdrawFNFT(salt, tempSupply);

        assertEq(
            USDC.balanceOf(alice), preBal - USDC.balanceOf(bob), "alice balance did not increase by expected amount"
        );
    }

    function testMetadataFunctions() public {
        uint256 amount = 1e6;
        uint256 supply = 1;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory supplies = new uint[](1);
        supplies[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockId: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        //TODO: Once we figure out the metadata handler
        //This is only meant to fill the coverage test

        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, supplies, config);

        assert(fnftHandler.exists(id));

        //TODO
        fnftHandler.uri(id);
        fnftHandler.renderTokenURI(id, alice);

        changePrank(revest.owner());
        revest.changeMetadataHandler(address(0xdead));
        assertEq(address(revest.metadataHandler()), address(0xdead), "metadata handler not updated");
    }
}
