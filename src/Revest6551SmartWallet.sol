// SPDX-License-Identifier: GNU-GPL v3.0 or later

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@solmate/utils/SSTORE2.sol";

import "./interfaces/IFNFTHandler.sol";
import "./interfaces/IERC6551Account.sol";

pragma solidity ^0.8.12;

contract Revest6551SmartWallet is IERC165, IERC6551Account, ReentrancyGuard {
    using SSTORE2 for address;

    IFNFTHandler public immutable handler;

    constructor() {
        handler = IFNFTHandler(msg.sender);
    }

    function executeCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory result) {

        uint length = address(this).code.length;
        uint tokenId = abi.decode(address(this).read(length - 0x20, length), (uint256));
        uint supply = handler.totalSupply(tokenId);

        uint balance = handler.balanceOf(msg.sender, tokenId);
        require(supply != 0 && balance == supply , "E008");

        (bool success, bytes memory returnData) = to.call{value: value}(data);
        require(success, "External Call Failed");
        return returnData;
    }

    function token()
        external
        view
        returns (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        )
    {
        uint256 length = address(this).code.length;
        return
            abi.decode(
                address(this).read(length - 0x60, length),
                (uint256, address, uint256)
            );
    }

    function owner() public pure returns (address) {
        return address(0);
    }


    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return (interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC6551Account).interfaceId);
    }

    receive() external payable {}

}