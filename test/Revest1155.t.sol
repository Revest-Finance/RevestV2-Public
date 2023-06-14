// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Revest_1155.sol";
import "src/TokenVault.sol";
import "src/LockManager_Timelock.sol";
import "src/LockManager_Addresslock.sol";

import "src/FNFTHandler.sol";
import "src/MetadataHandler.sol";

import "src/lib/PermitHash.sol";
import "src/interfaces/IAllowanceTransfer.sol";
import "src/lib/EIP712.sol";

import "@solmate/utils/SafeTransferLib.sol";

contract Revest1155Tests is Test {
    using PermitHash for IAllowanceTransfer.PermitBatch;
    using SafeTransferLib for ERC20;

    Revest_1155 public immutable revest;
    TokenVault public immutable vault;
    LockManager_Timelock public immutable lockManager_timelock;
    LockManager_Addresslock public immutable lockManager_addresslock;

    FNFTHandler public immutable fnftHandler;
    MetadataHandler public immutable metadataHandler;

    address public constant govController = address(0xdead);

    uint256 PRIVATE_KEY = vm.envUint("PRIVATE_KEY"); //Useful for EIP-712 Testing
    address alice = vm.rememberKey(PRIVATE_KEY);
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes signature;
    IAllowanceTransfer.PermitBatch permit;

    string baseURI = "https://ipfs.io/ipfs/";

    constructor() {
        vault = new TokenVault();
        metadataHandler = new MetadataHandler(baseURI);
        revest = new Revest_1155("", address(WETH), address(vault), address(metadataHandler), govController);

        lockManager_timelock = new LockManager_Timelock(address(WETH));
        lockManager_addresslock = new LockManager_Addresslock(address(WETH));

        fnftHandler = FNFTHandler(address(revest.fnftHandler()));

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(address(revest), "revest");
        vm.label(address(vault), "tokenVault");
        vm.label(address(fnftHandler), "fnftHandler");
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
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: false
        });

        config.handler = address(fnftHandler);

        uint256 currentTime = block.timestamp;
        (bytes32 salt, bytes32 lockId) =
            revest.mintTimeLock(block.timestamp + 1 weeks, recipients, supplies, amount, config);

        assertEq(revest.fnftIdToRevestId(id), salt, "salt was not calculated correctly");
        assertEq(revest.fnftIdToLockId(id), lockId, "lockId was not calculated correctly");

        vm.expectRevert(bytes("E015"));
        lockManager_timelock.createLock(keccak256(abi.encode("0xdead")), abi.encode(block.timestamp - 1 weeks));

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
            ILockManager.Lock memory lock = lockManager_timelock.getLock(lockId);
            assertEq(
                uint256(lockManager_timelock.lockType()),
                uint256(ILockManager.LockType.TimeLock),
                "lock type is not TimeLock"
            );

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

        assertFalse(lockManager_timelock.getLockMaturity(lockId, id));

        vm.expectRevert(bytes("E016"));
        lockManager_timelock.unlockFNFT(keccak256(abi.encode("0xdead")), 0);

        skip(1 weeks + 1 seconds);
        assertFalse(!lockManager_timelock.getLockMaturity(lockId, id));

        revest.unlockFNFT(salt);

        assertEq(lockManager_timelock.getTimeRemaining(lockId, 0), 0, "time remaining should be zero");

        revest.withdrawFNFT(salt, supply);

        assertEq(fnftHandler.balanceOf(bob, id), 0, "bob did not lose expected amount of FNFTs"); //All FNFTs were burned
        assertEq(USDC.balanceOf(bob), supply * amount, "bob did not receive expected amount of USDC"); //All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount"); //Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount"); //All funds were removed from SmartWallet

        assertEq(revest.fnftIdToRevestId(id), salt, "revestId was not set correctly");

        assertEq(revest.getAsset(salt), address(USDC), "asset was not set correctly");

        assertEq(revest.getValue(salt), 0, "value was not set correctly");

        supplies[0] = 0;
        vm.expectRevert(bytes("E012"));
        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, supplies, amount, config);

        supplies = new uint[](2);
        vm.expectRevert(bytes("E011"));
        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, supplies, amount, config);
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
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: false
        });

        config.handler = address(fnftHandler);

        (bytes32 salt, bytes32 lockId) =
            revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

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
            ILockManager.Lock memory lock = lockManager_timelock.getLock(lockId);
            assertEq(
                uint256(lockManager_timelock.lockType()),
                uint256(ILockManager.LockType.TimeLock),
                "lock type is not TimeLock"
            );
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
            handler: address(0),
            asset: address(USDC),
            lockManager: address(lockManager_addresslock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: false
        });

        config.handler = address(fnftHandler);
        (bytes32 salt, bytes32 lockId) = revest.mintAddressLock("", recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        ILockManager.Lock memory lock = lockManager_addresslock.getLock(lockId);
        assertEq(
            uint256(lockManager_addresslock.lockType()),
            uint256(ILockManager.LockType.AddressLock),
            "lock type is not AddressLock"
        );
        assertEq(lock.unlocked, false);
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        if (block.timestamp % 2 == 0) skip(1 seconds);

        assertFalse(lockManager_addresslock.getLockMaturity(lockId, id));

        vm.expectRevert(bytes("E006"));
        revest.withdrawFNFT(salt, supply); //Should revert because lock has not expired

        skip(1 seconds);
        assertFalse(!lockManager_addresslock.getLockMaturity(lockId, id));
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
            handler: address(0),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: false
        });

        (bytes32 salt,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

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

            assertEq(revest.getValue(salt), amount + additionalDepositAmount, "deposit amount was not updated");

            skip(1 weeks);

            fnftHandler.safeTransferFrom(alice, bob, id, tempSupply, "");

            changePrank(bob);
            revest.withdrawFNFT(salt, tempSupply);
            destroyAccount(walletAddr, address(this));
        }

        assertEq(
            USDC.balanceOf(bob), revest.getValue(salt) * tempSupply, "alice balance did not increase by expected amount"
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
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: true
        });

        (bytes32 salt, bytes32 lockId) =
            revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);
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
            vm.expectRevert(bytes("E015")); //Revert because new FNFT maturity date is in the past
            revest.extendFNFTMaturity(salt, block.timestamp - 2 weeks);

            vm.expectRevert(bytes("E007")); //Revert because new FNFT maturity date has already passed
            revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            rewind(2 weeks); //Go back 2 weeks to actually extend this time

            //Should revert because new unlockTime is not after current unlockTime
            vm.expectRevert(bytes("E010"));
            revest.extendFNFTMaturity(salt, block.timestamp + 1 days);

            uint256 currTime = block.timestamp;
            revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate

            uint256 newEndTime = lockManager_timelock.getLock(lockId).timeLockExpiry;
            assertEq(newEndTime, currTime + 2 weeks, "lock did not extend maturity by expected amount");

            skip(2 weeks);
            revest.withdrawFNFT(salt, supply);

            assertEq(USDC.balanceOf(alice), preBal, "alice balance did not increase by expected amount");
        }

        //Same Test but should fail to extend maturity because maturityExtension is false
        config.maturityExtension = false;

        (salt, lockId) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        bytes32 lockSalt = keccak256(abi.encode(salt, address(revest)));
        assertEq(lockManager_timelock.getTimeRemaining(lockSalt, 0), 1 weeks, "expected time not remaining");

        walletAddr = revest.getAddressForFNFT(salt);
        assertEq(USDC.balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount");

        vm.expectRevert(bytes("E009")); //Revert because FNFT is marked as non-extendable
        revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks); //Extend a week beyond the current endDate
    }

    function testMintFNFTWithEth(uint256 supply, uint256 amount) public {
        vm.assume(amount >= 1 ether && amount <= 100 ether);
        vm.assume(supply > 1 && supply <= 1e6);

        startHoax(alice, alice);

        uint256 preBal = alice.balance;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(fnftHandler),
            asset: address(0),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: id,
            maturityExtension: true
        });

        (bytes32 salt,) =
            revest.mintTimeLock{value: amount * supply}(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        address walletAddr = revest.getAddressForFNFT(salt);
        assertEq(
            ERC20(WETH).balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount"
        );

        assertEq(alice.balance, preBal - (supply * amount), "alice balance did not decrease by expected amountof ETH");
        IController.FNFTConfig memory storedConfig = revest.getFNFT(salt);

        assertEq(storedConfig.asset, ETH_ADDRESS, "asset was not set to ETH");
        assertEq(revest.getValue(salt), amount, "deposit amount was not set to amount");

        skip(1 weeks);
        revest.withdrawFNFT(salt, supply);
        assertEq(alice.balance, preBal, "alice balance did not increase by expected amount of ETH");

        preBal = alice.balance;
        uint256 wethPreBal = WETH.balanceOf(alice);
        (salt,) =
            revest.mintTimeLock{value: amount * supply}(block.timestamp + 1 weeks, recipients, amounts, amount, config);

        vm.expectRevert(bytes("E027"));
        revest.depositAdditionalToFNFT{value: 1 ether}(salt, 1 ether);

        revest.depositAdditionalToFNFT{value: (1 ether * supply)}(salt, 1 ether);
        revest.depositAdditionalToFNFT(salt, 1 ether);

        assertEq(
            alice.balance,
            preBal - (supply * (amount + 1 ether)),
            "alice balance did not decrease by expected amount of ETH"
        );
        assertEq(
            WETH.balanceOf(alice),
            wethPreBal - (supply * (1 ether)),
            "alice balance did not decrease by expected amount of WETH"
        );

        storedConfig = revest.getFNFT(salt);
        assertEq(storedConfig.asset, ETH_ADDRESS, "asset was not set to ETH");
        assertEq(revest.getValue(salt), amount + 2 ether, "deposit amount was not set to amount");

        skip(1 weeks);

        revest.withdrawFNFT(salt, supply);
        assertEq(alice.balance, preBal + (1 ether * supply), "alice balance did not increase by expected amount of ETH");
    }

    function testTransferFNFTWithSignature() public {
        startHoax(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: id,
            maturityExtension: true
        });

        revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, 1e6, config);

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
    }

    function testProxyCallFunctionality() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory amounts = new uint[](1);
        amounts[0] = 2;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: id,
            maturityExtension: true
        });

        (bytes32 salt,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, 1e6, config);
        address walletAddr = revest.getAddressForFNFT(salt);

        address[] memory targets = new address[](1);
        targets[0] = address(USDC);
        uint256[] memory values = new uint[](1);
        bytes[] memory calldatas = new bytes[](1);

        //Blacklist transfer function
        changePrank(alice);

        //Transfer tokens out of the vault
        calldatas[0] = abi.encodeWithSelector(USDC.transfer.selector, bob, 1e6);

        //Expect Revert because invokes a blacklisted function
        vm.expectRevert(bytes("E013"));
        revest.proxyCall(salt, targets, values, calldatas);

        //Should succeed because valid proxy call to invoke
        calldatas[0] = abi.encodeWithSelector(USDC.totalSupply.selector);
        bytes[] memory returnDatas = revest.proxyCall(salt, targets, values, calldatas);
        destroyAccount(walletAddr, address(this));

        //Should Succeed because even though you call WETH, you aren't doing a blacklisted function
        calldatas[0] = abi.encodeWithSelector(IERC20.totalSupply.selector);
        revest.proxyCall(salt, targets, values, calldatas);
        destroyAccount(walletAddr, address(this));

        assertEq(abi.decode(returnDatas[0], (uint256)), USDC.totalSupply(), "return data does not match expected value");

        fnftHandler.safeTransferFrom(alice, bob, id, 1, "");

        //Should revert because you no longer own the entire supply of the FNFT
        vm.expectRevert(bytes("E007"));
        revest.proxyCall(salt, targets, values, calldatas);

        skip(1 weeks);
        config.asset = ETH_ADDRESS;
        targets[0] = address(WETH);
        (salt,) = revest.mintTimeLock{value: 2 ether}(block.timestamp + 1 weeks, recipients, amounts, 1 ether, config);
        calldatas[0] = abi.encodeWithSelector(IWETH.withdraw.selector, 1 ether);

        //Should revert by trying to unwrap the WETH
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
                handler: address(fnftHandler),
                asset: address(USDC),
                lockManager: address(lockManager_timelock),
                nonce: 0,
                fnftId: id,
                maturityExtension: true
            });

            vm.expectRevert(bytes("E024"));
            revest.mintTimeLockWithPermit(
                block.timestamp + 1 weeks, recipients, amounts, uint256(amount), config, permit, ""
            );

            (salt, lockId) = revest.mintTimeLockWithPermit(
                block.timestamp + 1 weeks, recipients, amounts, uint256(amount), config, permit, signature
            );
        }

        assertEq(fnftHandler.balanceOf(alice, id), 1, "FNFT not minted");
        assertEq(USDC.balanceOf(revest.getAddressForFNFT(salt)), amount, "USDC not deposited into vault");

        //Test that Lock was created
        ILockManager.Lock memory lock = lockManager_timelock.getLock(lockId);
        assertEq(
            uint256(lockManager_timelock.lockType()),
            uint256(ILockManager.LockType.TimeLock),
            "lock type is not TimeLock"
        );
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
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_addresslock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: false
        });

        vm.expectRevert(bytes("E024"));
        revest.mintAddressLockWithPermit("", recipients, amounts, uint256(amount), config, permit, "");

        (bytes32 salt, bytes32 lockId) =
            revest.mintAddressLockWithPermit("", recipients, amounts, uint256(amount), config, permit, signature);

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        ILockManager.Lock memory lock = lockManager_addresslock.getLock(lockId);
        assertEq(
            uint256(lockManager_addresslock.lockType()),
            uint256(ILockManager.LockType.AddressLock),
            "lock type is not AddressLock"
        );
        assertEq(lock.unlocked, false);
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        if (block.timestamp % 2 == 0) skip(1 seconds);

        vm.expectRevert(bytes("E006"));
        revest.withdrawFNFT(salt, supply); //Should revert because lock has not expired

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
                handler: address(fnftHandler),
                asset: address(USDC),
                lockManager: address(lockManager_timelock),
                nonce: 0,
                fnftId: 0,
                maturityExtension: false
            });

            (salt,) = revest.mintTimeLock(block.timestamp + 1 weeks, recipients, amounts, amount, config);
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

            assertEq(revest.getValue(salt), amount + additionalDepositAmount, "deposit amount was not updated");
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
                revest.getValue(salt) * tempSupply,
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
        uint256 amount = 1.5e6;
        uint256 supply = 1;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        uint256[] memory supplies = new uint[](1);
        supplies[0] = supply;

        uint256 id = fnftHandler.getNextId();

        IController.FNFTConfig memory config = IController.FNFTConfig({
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager_timelock),
            nonce: 0,
            fnftId: 0,
            maturityExtension: false
        });

        //TODO: Once we figure out the metadata handler
        //This is only meant to fill the coverage test

        (bytes32 salt, ) = revest.mintTimeLock(block.timestamp + 1 weeks + 6 hours, recipients, supplies, amount, config);
        skip(2 weeks);
        assert(fnftHandler.exists(id));

        //TODO
        string memory uri = fnftHandler.uri(id);
        (string memory baseRenderURI,) = fnftHandler.renderTokenURI(id, alice);

        string memory metadata = metadataHandler.generateMetadata(address(revest), salt);

        console.log("uri: %s", uri);
        console.log("------------------");
        console.log("baseRenderURI: %s", baseRenderURI);
        console.log("------------------");
        console.log("metadata: %s", metadata);

        changePrank(revest.owner());
        revest.changeMetadataHandler(address(0xdead));
        assertEq(address(revest.metadataHandler()), address(0xdead), "metadata handler not updated");
    }
}
