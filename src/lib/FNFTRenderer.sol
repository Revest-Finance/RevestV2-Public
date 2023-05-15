pragma solidity ^0.8.14;

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


library FNFTRenderer {
    //Address Lock 
    struct RenderParams {
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

    function render(RenderParams memory param) {
        string memory image = string.concat();

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
        description = string.concat();
    }


}