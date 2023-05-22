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
            ", LockType: ", 
            lockType, 
            ", Amount: ", Strings.toHexString(amount), 
            ", Receiver: ", Strings.toHexString(uint256(uint160(unlockAddress)), 20)
        );
    }

    function renderBackground(
        address unlockAddress
    ) internal pure returns (string memory background) {
        // bytes32 key = keccack256(abi.encodepacked(owner));
        // uint256 hue = uint256(key) % 360;

        string memory addressString = Strings.toHexString(unlockAddress);

        background =
            '<rect width="300" height="480" fill="hsl(0,0%,100%)" /> <rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(0,0%,18%)" stroke="#000" /> '
        ;
        background = string.concat(background,'<svg xmlns="http://www.w3.org/2000/svg" width="100" x="100" id="Default" viewBox="0 0 576.01 575.06"><defs><style>.cls-1{fill:#ffa800;}</style></defs><path class="cls-1" d="M287.62,676a4.72,4.72,0,0,0-4.33-4.7C135.92,659.1,24.4,532.85,30.49,385.11S158.13,120.73,306,120.73,575.42,237.36,581.51,385.11s-105.43,274-252.8,286.17a4.72,4.72,0,0,0-4.33,4.7v2.84a4.74,4.74,0,0,0,1.52,3.46,4.68,4.68,0,0,0,3.58,1.23c154-12.59,270.59-144.43,264.28-298.79S460.49,108.47,306,108.47,24.54,230.36,18.24,384.72s110.31,286.2,264.28,298.79a4.71,4.71,0,0,0,5.1-4.69V676" transform="translate(-18 -108.47)"/></svg>');
        background = string.concat(background, '<svg width = "10" x = "145" id="Default" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 549.88 768"><defs><style>.cls-1{fill:#ccc;}</style></defs><path class="cls-1" d="M196,340.1H113.54V204.46C113.54,98.26,199.8,12,306,12S498.46,98.26,498.46,204.46V340.1H416V204.46a110,110,0,0,0-220,0V340.1" transform="translate(-31.06 -12)"/><path class="cls-1" d="M31.06,725a55,55,0,0,0,55,55H526a55,55,0,0,0,55-55V450.07a55,55,0,0,0-55-55H86.05a55,55,0,0,0-55,55V725" transform="translate(-31.06 -12)"/></svg>');
        background =  string.concat(background, '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="90" version="1.1" id="Default" x="105px" y="0px" viewBox="0 0 514.7 514.7" style="enable-background:new 0 0 514.7 514.7;" xml:space="preserve">   <style type="text/css">     .st0{fill:#7d7d7d;}   </style>   <path class="st0" d="M0.7,276.9c-6.3-83,27.9-163.9,91.8-217.2l142.2,82.1L0.7,276.9"/>   <path class="st0" d="M146,489.4c-75-36-128-106.1-142.2-188.2L146,219.1V489.4"/>   <path class="st0" d="M112.1,44.9c68.7-47,155.9-57.8,234-29.1V180L112.1,44.9"/>   <path class="st0" d="M368.8,25.4c75,36,128,106.1,142.2,188.1l-142.2,82.1V25.4"/>   <path class="st0" d="M514,237.8c6.3,83-27.9,163.9-91.8,217.2L280,372.9L514,237.8"/>   <path class="st0" d="M402.6,469.8c-68.7,47-155.9,57.8-234,29.1V334.7L402.6,469.8"/>   </svg> ');
        background = string.concat(background, ' <style>     .tokens {       font: bold 30px sans-serif;     }      .fee {       font: normal 26px sans-serif;     }      .tick {       font: normal 18px sans-serif;     }   </style>');
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
            '<text x="39" y="360" class="tick" fill="#fff">',
            Strings.toString(amount),
            "</text>",
            '<rect x="30" y="372" width="240" height="24"/>',
            '<text x="39" y="360" dy="30" class="tick" fill="#fff">',
            lockType,
            "</text>"
            '<rect x="30" y="402" width="240" height="24"/>',
            '<text x="39" y="360" dy="60" class="tick" fill="#fff">UnlockAddress: ',
            Strings.toHexString(uint256(uint160(unlockAddress)), 20),
            "</text>"
        );
    }







}