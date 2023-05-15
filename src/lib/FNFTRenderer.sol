pragma solidity ^0.8.14;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


library FNFTRenderer {
    //Address Lock 
    struct RenderParams {
        string assetName;
        string assetTicker;
        uint256 amount;
        uint256 id;
        uint256 createTime; //TODO: turn into uint96
        string lockType;
        address outputReceiver;
        bool maturityExtension; // Maturity extensions remaining
        bool useETH;
        bool nontransferrable;
    }

    function render(RenderParams memory param) internal view returns (string memory) {
        string memory image = string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 480'>",
            "<style>.tokens { font: bold 30px sans-serif; }",
            ".fee { font: normal 26px sans-serif; }",
            ".tick { font: normal 18px sans-serif; }</style>",
            renderBackground(param.outputReceiver),
            renderTop(param.assetName, param.assetTicker),
            renderBottom(param.amount, param.lockType ),
            "</svg>"
        );

        string memory description = renderDescription();

        string memory json = string.concat();

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
        uint256 amount,
        uint id, 
        string memory lockType,
        address outputReceiver
    ) internal pure returns (string memory description) {
        description = string.concat(
            "Receiver: ", abi.encodePacked(outputReceiver_, 
            "Amount: ", amount, 
            "LockType: ", lockType, 
            "ID: ", id
        );
    }

    function renderBackground(
        address owner
    ) internal pure returns (string memory background) {
        // bytes32 key = keccack256(abi.encodepacked(owner));
        // uint256 hue = uint256(key) % 360;

        string memory addressString = abi.encodePacked(address);

        background = string.concat(
            '<rect width="300" height="480" fill="hsl(',
            addressString,  
            ',40%,40%)"/>',
            '<rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(',
            addressString, 
            ',100%,50%)" stroke="#000"/>'
        );
    }

    function renderTop(
        string memory assetName, 
        string memory assetTicker
    ) internal pure returns (string memory top) {
        top = string.concat(
            '<rect x="30" y="87" width="240" height="42"/>',
            '<text x="39" y="120" class="tokens" fill="#fff">',
            assetName,
            "/",
            assetTicker,
            "</text>"
            '<rect x="30" y="132" width="240" height="30"/>',
            '<text x="39" y="120" dy="36" class="fee" fill="#fff">',
            assetName,
            "</text>"
        );
    }

    function renderBottom(
        uint256 amount, 
        string memory lockType
    ) internal pure returns (string memory bottom) {
        bottom = string.concat(
            '<rect x="30" y="342" width="240" height="24"/>',
            '<text x="39" y="360" class="tick" fill="#fff">Lower tick: ',
            lockType,
            "</text>",
            '<rect x="30" y="372" width="240" height="24"/>',
            '<text x="39" y="360" dy="30" class="tick" fill="#fff">Upper tick: ',
            lockType,
            "</text>"
        );
    }







}