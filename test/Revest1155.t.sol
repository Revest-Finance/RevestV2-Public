// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "src/Revest_1155.sol";
import "src/TokenVault.sol";
import "src/LockManager.sol";
import "src/FNFTHandler.sol";
import "./ExampleAddressLock.sol";

contract Revest1155Tests is Test {

    Revest_1155 public immutable revest;
    TokenVault public immutable vault;
    LockManager public immutable lockManager;
    FNFTHandler public immutable fnftHandler;
    ExampleAddressLock public immutable addressLock;

    uint PRIVATE_KEY = vm.envUint("PRIVATE_KEY");//Useful for EIP-712 Testing
    address alice = vm.rememberKey(PRIVATE_KEY);
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    ERC20 WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    constructor() {
        vault = new TokenVault();
        revest = new Revest_1155(address(WETH), address(vault));
        lockManager = new LockManager();
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

        fnftHandler.transferOwnership(address(revest));//Transfer ownership to Revest from deployer

        deal(address(WETH), alice, 1000 ether);
        deal(address(USDC), alice, 1e10);

        startHoax(alice, alice);
        USDC.approve(address(revest), type(uint).max);
        USDC.approve(PERMIT2, type(uint).max);

        WETH.approve(address(revest), type(uint).max);
        WETH.approve(PERMIT2, type(uint).max);
        vm.stopPrank();
    }

    function setUp() public {
        hoax(alice, alice);
    }

    function testMintTimeLockToAlice(uint supply, uint amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6);

        uint preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockSalt: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);

        //Check Minting was successful
        {
            //Funds were deducted from alice
            uint postBal = USDC.balanceOf(alice);
            assertEq(postBal, preBal - (supply * amount), "balance did not decrease by expected amount");
        
            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), supply * amount, "vault balance did not increase by expected amount"); 

            //FNFTs were minted to alice
            assertEq(fnftHandler.balanceOf(alice, id), supply, "alice did not receive expected amount of FNFTs");
            assertEq(fnftHandler.totalSupply(id), supply, "total supply of FNFTs did not increase by expected amount");

            //Lock was created
            IRevest.Lock memory lock = lockManager.getLock(lockId);
            assertEq(uint(lock.lockType), uint(IRevest.LockType.TimeLock), "lock type is not TimeLock");
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);
        }
        
        //Transfer the FNFT from Alice -> Bob
        {
            fnftHandler.safeTransferFrom(alice, bob, id, supply, "");
            assertEq(fnftHandler.balanceOf(alice, id), 0, "alice did not lose expected amount of FNFTs");
            assertEq(fnftHandler.balanceOf(bob, id), supply, "bob did not receive expected amount of FNFTs");
        }
        
        changePrank(bob);
        vm.expectRevert(bytes("E015"));
        revest.withdrawFNFT(salt, supply);

        skip(1 weeks);
        revest.withdrawFNFT(salt, supply);
        assertEq(fnftHandler.balanceOf(bob, id), 0, "bob did not lose expected amount of FNFTs");//All FNFTs were burned
        assertEq(USDC.balanceOf(bob), supply * amount, "bob did not receive expected amount of USDC");//All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount");//Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount");//All funds were removed from SmartWallet
        
    }

    function testBatchMintTimeLock(uint supply, uint amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6);

        uint preBal = USDC.balanceOf(alice);

        //Mint half to bob and half to alice
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = supply / 2;
        amounts[1] = supply / 2;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockSalt: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);

        {
            //Funds were deducted from alice
            uint postBal = USDC.balanceOf(alice);
            assertEq(postBal, preBal - (supply * amount), "balance did not decrease by expected amount");
        
            //Funds were moved into the smart wallet
            assertEq(USDC.balanceOf(walletAddr), supply * amount, "vault balance did not increase by expected amount");

            //FNFTs were minted to alice and Bob
            assertEq(fnftHandler.balanceOf(alice, id), supply / 2, "alice did not receive expected amount of FNFTs");
            assertEq(fnftHandler.balanceOf(bob, id), supply / 2, "alice did not receive expected amount of FNFTs");
            assertEq(fnftHandler.totalSupply(id), supply, "total supply of FNFTs did not increase by expected amount");

            //Lock was created
            IRevest.Lock memory lock = lockManager.getLock(lockId);
            assertEq(uint(lock.lockType), uint(IRevest.LockType.TimeLock), "lock type is not TimeLock");
            assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock expiry is not expected value");
            assertEq(lock.unlocked, false);
        }

        vm.expectRevert();
        revest.withdrawFNFT(salt, supply);//Should Revert for trying to burn more than balance

        vm.expectRevert(bytes("E015"));
        revest.withdrawFNFT(salt, supply / 2);//Should revert because lock is not expired

        skip(1 weeks);

        revest.withdrawFNFT(salt, supply / 2);//Should execute correctly

        assertEq(USDC.balanceOf(alice), preBal / 2, "alice did not receive expected amount of USDC");
        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice did not receive expected amount of FNFTs");
        assertEq(fnftHandler.totalSupply(id), supply / 2, "total supply of FNFTs did not decrease by expected amount");
        assertEq(USDC.balanceOf(walletAddr), (supply * amount) / 2, "vault balance did not decrease by expected amount");
        assertEq(fnftHandler.balanceOf(bob, id), fnftHandler.totalSupply(id), "expected and actual FNFT supply do not match");

    }

    function testMintAddressLock_implementsInterface(uint supply, uint amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6);

        uint preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockSalt: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintAddressLock(
            0,
            address(addressLock),
            0,
            "",
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        IRevest.Lock memory lock = lockManager.getLock(lockId);
        assertEq(uint(lock.lockType), uint(IRevest.LockType.AddressLock), "lock type is not AddressLock");
        assertEq(lock.unlocked, false);
        assertEq(lock.addressLock, address(addressLock), "address lock is not expected value");
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        if (block.timestamp % 2 == 0) skip(1 seconds);

        vm.expectRevert(bytes("E021"));
        revest.withdrawFNFT(salt, supply);//Should revert because lock has not expired

        skip(1 seconds);
        revest.withdrawFNFT(salt, supply);

        //Check that the lock was unlocked and all funds returned to alice
        assertEq(fnftHandler.balanceOf(alice, id), 0, "bob did not lose expected amount of FNFTs");//All FNFTs were burned
        assertEq(USDC.balanceOf(alice), preBal, "bob did not receive expected amount of USDC");//All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount");//Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount");//All funds were removed from SmartWallet

    }

    function testMintAddressLock_sendsSignal(uint supply, uint amount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6);

        uint preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockSalt: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockId) = revest.mintAddressLock(
            0,
            carol,//Set carol as the unlocker
            0,
            "",
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);

        //Lock was created
        IRevest.Lock memory lock = lockManager.getLock(lockId);
        assertEq(uint(lock.lockType), uint(IRevest.LockType.AddressLock), "lock type is not AddressLock");
        assertEq(lock.unlocked, false);
        assertEq(lock.addressLock, address(addressLock), "address lock is not expected value");
        assertEq(lock.creationTime, block.timestamp, "lock creation time is not expected value");

        if (block.timestamp % 2 == 0) skip(1 seconds);

        vm.expectRevert(bytes("E021"));
        revest.withdrawFNFT(salt, supply);//Should revert because carol has not approved it yet

        //Have Carol unlock the FNFT
        changePrank(carol);
        revest.unlockFNFT(salt);

        //Change back to Alice and have her withdraw the FNFT
        changePrank(alice);
        revest.withdrawFNFT(salt, supply);

        //Check that the lock was unlocked and all funds returned to alice
        assertEq(fnftHandler.balanceOf(alice, id), 0, "bob did not lose expected amount of FNFTs");//All FNFTs were burned
        assertEq(USDC.balanceOf(alice), preBal, "bob did not receive expected amount of USDC");//All funds were returned to bob
        assertEq(fnftHandler.totalSupply(id), 0, "total supply of FNFTs did not decrease by expected amount");//Total supply of FNFTs was decreased
        assertEq(USDC.balanceOf(walletAddr), 0, "vault balance did not decrease by expected amount");//All funds were removed from SmartWallet
    }

    function testDepositAdditionalToToFNFT(uint supply, uint amount, uint additionalDepositAmount) public {
        vm.assume(supply % 2 == 0 && supply >= 2);
        vm.assume(amount >= 1e6);
        vm.assume(additionalDepositAmount >= 1e6);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockSalt: bytes32(0),
            maturityExtension: false,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt,) = revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);
        uint balanceBefore = USDC.balanceOf(walletAddr);
        uint aliceBalanceBeforeAdditionalDeposit = USDC.balanceOf(alice);

        //Prevents a stack too deep error
        uint tempSupply = supply/2;
        
        {
            revest.depositAdditionalToFNFT(salt, additionalDepositAmount);
            assertEq(USDC.balanceOf(walletAddr), balanceBefore + additionalDepositAmount * supply, "vault balance did not increase by expected amount");
            assertEq(USDC.balanceOf(alice), aliceBalanceBeforeAdditionalDeposit - (additionalDepositAmount * supply), "alice balance did not decrease by expected amount");
            assertEq(revest.getFNFT(salt).depositAmount, amount + additionalDepositAmount, "deposit amount was not updated");
       
            skip(1 weeks);

            fnftHandler.safeTransferFrom(alice, bob, id, tempSupply, "");

            changePrank(bob);
            revest.withdrawFNFT(salt, tempSupply);
            changePrank(alice);
            revest.withdrawFNFT(salt, tempSupply);
        }

        uint bobSupply = fnftHandler.balanceOf(bob, id);
        assertEq(USDC.balanceOf(bob), revest.getFNFT(salt).depositAmount * bobSupply, "alice balance did not increase by expected amount");
        assertEq(USDC.balanceOf(alice), ((tempSupply) * amounts[0]) + ((tempSupply) * additionalDepositAmount), "alice balance did not increase by expected amount");
    }

    function mintTimeLockAndExtendMaturity(uint supply, uint amount) public {
        vm.assume(amount >= 1e6);

        uint preBal = USDC.balanceOf(alice);

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: 0,
            lockSalt: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: false
        });

        (bytes32 salt, bytes32 lockSalt) = revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );
            address walletAddr;

        {
            walletAddr = revest.getAddressForFNFT(salt);
            assertEq(USDC.balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount");
            
            fnftHandler.safeTransferFrom(alice, bob, id, 1, "");
            vm.expectRevert(bytes("E008"));//Revert because you don't own the entire supply of the FNFT
            revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks);//Extend a week beyond the current endDate

            //Send it back to Alice so she can extend maturity
            changePrank(bob);
            fnftHandler.safeTransferFrom(bob, alice, id, 1, "");
            
            changePrank(alice);
            
            skip(2 weeks);
            vm.expectRevert(bytes("E007"));//Revert because FNFT maturity has already passed

            rewind(2 weeks);//Go back 2 weeks to actually extend this time
            revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks);//Extend a week beyond the current endDate

            skip(2 weeks);
            revest.withdrawFNFT(salt, supply);

            assertEq(USDC.balanceOf(alice), preBal, "alice balance did not increase by expected amount");
            uint newEndTime = lockManager.getLock(lockSalt).timeLockExpiry;
            assertEq(newEndTime, block.timestamp + 2 weeks, "lock did not extend maturity by expected amount");
        }

        //Same Test but should fail to extend maturity because maturityExtension is false
        config.maturityExtension = false;

        (salt, lockSalt) = revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        walletAddr = revest.getAddressForFNFT(salt);
        assertEq(USDC.balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount");

        vm.expectRevert(bytes("E009"));//Revert because FNFT is marked as non-extendable
        revest.extendFNFTMaturity(salt, block.timestamp + 2 weeks);//Extend a week beyond the current endDate
    }

    function testMintFNFTWithEth(uint supply, uint amount) public {
        vm.assume(amount >= 1 ether);
        vm.assume(supply != 0);

        uint preBal = alice.balance;

        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(0),
            lockManager: address(lockManager),
            depositAmount: amount,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockSalt: bytes32(0),
            maturityExtension: true,
            useETH: true,
            nontransferrable: false
        });

        (bytes32 salt,) = revest.mintTimeLock{value: amount}(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        address walletAddr = revest.getAddressForFNFT(salt);
        assertEq(ERC20(WETH).balanceOf(walletAddr), amount * supply, "vault balance did not increase by expected amount");
        assertEq(alice.balance, preBal - (supply * amount), "alice balance did not decrease by expected amountof ETH");
        IRevest.FNFTConfig memory storedConfig = revest.getFNFT(salt);
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
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockSalt: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: true
        });

        revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        vm.expectRevert(bytes("E022"));//Revert because FNFT is marked as non-transferrable
        fnftHandler.safeTransferFrom(alice, bob, id, 1, "");

        fnftHandler.safeTransferFrom(alice, address(0), id, 1, "");
        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice still owns FNFT");
        assertEq(fnftHandler.balanceOf(address(0), id), 1, "alice still owns FNFT");
    
    }

    function testMintFNFTWithExistingLock() public {
        uint preBal = USDC.balanceOf(alice);
        
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockSalt: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: true
        });

        (bytes32 salt1, bytes32 lockSalt) = revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );
        

        (bytes32 salt2, bytes32 lockSalt2) = revest.mintTimeLock(
            0,
            block.timestamp + 3 weeks,
            lockSalt,
            recipients,
            amounts,
            config
        );

        assertEq(lockSalt, lockSalt2, "lockSalts do not match");

        IRevest.FNFTConfig memory timelock1 = revest.getFNFT(salt1);
        IRevest.FNFTConfig memory timelock2 = revest.getFNFT(salt2);
        assertEq(timelock1.lockSalt, timelock2.lockSalt, "lockSalts do not match");
        IRevest.Lock memory lock = lockManager.getLock(lockSalt);

        assertEq(lock.timeLockExpiry, block.timestamp + 1 weeks, "lock did not extend maturity by expected amount");
        skip(1 weeks);

        revest.withdrawFNFT(salt1, 1);

        bool unlocked = lockManager.getLockMaturity(lockSalt, id);
        assertEq(unlocked, true, "lock was not unlocked");
        revest.withdrawFNFT(salt2, 1);

        assertEq(USDC.balanceOf(alice), preBal, "alice did not receive expected amount of USDC");
    }

    function testTransferFNFTWithSignature() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1;

        uint id = fnftHandler.getNextId();

        IRevest.FNFTConfig memory config = IRevest.FNFTConfig({
            pipeToContract: address(0),
            handler: address(fnftHandler),
            asset: address(USDC),
            lockManager: address(lockManager),
            depositAmount: 1e6,
            nonce: 0,
            quantity: 0,
            fnftId: id,
            lockSalt: bytes32(0),
            maturityExtension: true,
            useETH: false,
            nontransferrable: true
        });

        revest.mintTimeLock(
            0,
            block.timestamp + 1 weeks,
            0,
            recipients,
            amounts,
            config
        );

        bytes32 SETAPPROVALFORALL_TYPEHASH = keccak256("transferFromWithPermit(address owner,address operator, bool approved, uint id, uint amount, uint256 deadline, uint nonce, bytes data)");
        bytes32 DOMAIN_SEPARATOR = fnftHandler.DOMAIN_SEPARATOR();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(SETAPPROVALFORALL_TYPEHASH, alice, bob, true, id, 1, block.timestamp + 1 weeks, 0, bytes("")))
            )
        );

        //Sign the permit info
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, digest);
        bytes memory signature = abi.encode(v, r, s);

        //The Permit info itself
        IFNFTHandler.permitApprovalInfo memory permit = IFNFTHandler.permitApprovalInfo({
            owner: alice,
            operator: bob,
            id: id,
            amount: 1,
            deadline: block.timestamp + 1 weeks,
            data: bytes("")
        });

        //Do the transfer
        fnftHandler.transferFromWithPermit(permit, signature);

        assertEq(fnftHandler.balanceOf(alice, id), 0, "alice still owns FNFT");
        assertEq(fnftHandler.balanceOf(bob, id), 1, "bob does not own FNFT");
        assertEq(fnftHandler.isApprovedForAll(alice, bob), true);
    }

    function testMintingWithPermit2(uint amount) public {

    }

    function testProxyCallFunctionality() public {

    }


}