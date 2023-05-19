pragma solidity ^0.8.14;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


library FNFTRenderer {
    //Lock
    struct RenderParams {
        //properties
        string assetName;
        string assetTicker;
        uint256 amount;
        string lockType;
        address unlockAddress;
    }

    function render(RenderParams memory param) internal view returns (string memory) {
        string memory image = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 480'>",
            "<style>.tokens { font: bold 30px sans-serif; }",
            ".fee { font: normal 26px sans-serif; }",
            ".tick { font: normal 18px sans-serif; }</style>",
            renderBackground(param.unlockAddress),
            renderTop(param.assetName, param.assetTicker),
            renderBottom(param.amount, param.lockType, param.unlockAddress),
            "</svg>"
        );

        string memory description = renderDescription(param.assetName, param.assetTicker, param.amount, param.lockType, param.unlockAddress);

        string memory json = string.concat(
            '{"name" : "Time Lock FNFT - RVST",',
            '"description":"',
            description,
            '",',
            '"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(image)),
            '"}'
        );

        return
            string.concat(
                "data:application/json;base64,",
                Base64.encode(bytes(json))
            );

    }


    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////

    function renderDescription(
        string memory assetName, 
        string memory assetTicker,
        uint256 amount, 
        string memory lockType,
        address unlockAddress
    ) internal pure returns (string memory description) {
        description = string.concat(
            assetName, 
            " ", 
            assetTicker, 
            " LockType: ", 
            lockType, 
            " Amount: ", Strings.toHexString(amount), 
            " Receiver: ", Strings.toHexString(uint256(uint160(unlockAddress)), 20)
        );
    }

    function renderBackground(
        address unlockAddress
    ) internal pure returns (string memory background) {
        // bytes32 key = keccack256(abi.encodepacked(owner));
        // uint256 hue = uint256(key) % 360;

        string memory addressString = Strings.toHexString(unlockAddress);

        background =
            '<rect width="300" height="480" fill="hsl(0,0%,100%)" /> <rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(0,0%,18%)" stroke="#000" />'
        ;
    }

    function renderTop(
        string memory assetName, 
        string memory assetTicker
    ) internal pure returns (string memory top) {
        top = string.concat(
            '<rect x="30" y="87" width="240" height="42"/>',
            '<text x="39" y="120" class="tokens" fill="#fff">',
            assetName,
            "</text>"
            '<rect x="30" y="132" width="240" height="30"/>',
            '<text x="39" y="120" dy="36" class="fee" fill="#fff">',
            assetTicker,
            "</text>"
        );
    }

    function renderBottom(
        uint256 amount, 
        string memory lockType,
        address unlockAddress
    ) internal pure returns (string memory bottom) {
        bottom = string.concat(
            '<rect x="30" y="342" width="240" height="24"/>',
            '<text x="39" y="360" class="tick" fill="#fff">Amount: ',
            Strings.toHexString(amount),
            "</text>",
            '<rect x="30" y="372" width="240" height="24"/>',
            '<text x="39" y="360" dy="30" class="tick" fill="#fff">Type Lock: ',
            lockType,
            "</text>"
            '<rect x="30" y="372" width="240" height="24"/>',
            '<text x="39" y="360" dy="30" class="tick" fill="#fff">UnlockAddress: ',
            Strings.toHexString(uint256(uint160(unlockAddress)), 20),
            "</text>"
        );
    }







}