pragma solidity >=0.8.12;

import "forge-std/Script.sol";

import "src/Revest_1155.sol";
import "src/Revest_721.sol";
import "src/LockManager_Timelock.sol";
import "src/TokenVault.sol";
import "src/FNFTHandler.sol";
import "src/MetadataHandler.sol";

interface ICREATE3Factory {
    /// @notice Deploys a contract using CREATE3
    /// @dev The provided salt is hashed together with msg.sender to generate the final salt
    /// @param salt The deployer-specific salt for determining the deployed contract's address
    /// @param creationCode The creation code of the contract to deploy
    /// @return deployed The address of the deployed contract
    function deploy(bytes32 salt, bytes memory creationCode)
        external
        payable
        returns (address deployed);
}

contract RevestV2_deployment is Script {
    
    //Deployed Omni-Chain
    ICREATE3Factory factory = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    //Replace with WETH on destination Chain
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //Replace with Timelock GovController on destination Chain
    address govController = address(0xdead);

    string URI_BASE_METADATA_HANDLER = "";
    string URI_BASE_FNFT_HANDLER = "";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);

        vm.startBroadcast(deployer);

        //Deploy TokenVault
        address tokenVault = factory.deploy(keccak256(abi.encode("TokenVault")), type(TokenVault).creationCode);

        //Deploy Lock Manager Timelock Contract
        bytes memory lockManager_creationCode = abi.encodePacked(type(LockManager_Timelock).creationCode, abi.encode(WETH));
        address lockManager_timelock = factory.deploy(keccak256(abi.encode("")), lockManager_creationCode);

        //Deploy Metadata Handler
        bytes memory MetadataHandler_creationCode = abi.encodePacked(type(MetadataHandler).creationCode, abi.encode(tokenVault, URI_BASE_METADATA_HANDLER));
        address metadataHandler = factory.deploy(keccak256(abi.encode("MetadataHandler")), MetadataHandler_creationCode);

        //Deploy Revest 1155
        bytes memory Revest_1155_creationCode = abi.encodePacked(type(Revest_1155).creationCode, abi.encode(WETH, tokenVault, metadataHandler, govController));
        address revest_1155 = factory.deploy(keccak256(abi.encode("Revest_1155")), Revest_1155_creationCode);

        //Deploy Revest 721
        bytes memory Revest_721_creationCode = abi.encodePacked(type(Revest_721).creationCode, abi.encode(WETH, tokenVault, metadataHandler, govController));
        address revest_721 = factory.deploy(keccak256(abi.encode("Revest_721")), Revest_721_creationCode);

        //Deploy FNFT Handler
        bytes memory FNFTHandler_creationCode = abi.encodePacked(type(FNFTHandler).creationCode, abi.encode(revest_1155, URI_BASE_FNFT_HANDLER));
        address fnftHandler = factory.deploy(keccak256(abi.encode("FNFTHandler")), FNFTHandler_creationCode);

        //Transfer Ownership of FNFTHandler to 1155
        require(FNFTHandler(fnftHandler).owner() == revest_1155, "Ownership Transfer Failed");
        console.log("---FNFT Handler Ownership Transfered to Revest 1155---");

        vm.stopBroadcast();

        console.log("Token Vault: %s: ", tokenVault);
        console.log("Lock Manager Timelock: %s: ", lockManager_timelock);
        console.log("Metadata Handler: %s: ", metadataHandler);
        console.log("Revest 1155: %s: ", revest_1155);
        console.log("Revest 721: %s: ", revest_721);
        console.log("FNFT Handler: %s: ", fnftHandler);

    }

}

