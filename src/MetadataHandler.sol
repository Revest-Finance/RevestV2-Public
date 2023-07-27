// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/IMetadataHandler.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";

import "forge-std/console.sol";

/**
 * @title MetadataHandler
 * @author 0xTraub
 */
contract MetadataHandler is IMetadataHandler {
    using ERC165Checker for address;
    using Strings for *;

    string public renderURI;
    string private animation_base;

    string public constant isUnlockedColor = "#00ff54";
    string public constant isLockedColor = "#e4a238";

    constructor(string memory animBase) {
        animation_base = animBase;
    }

    function getTokenURI(uint fnftId) external view override returns (string memory) {
        return string(
            abi.encodePacked(animation_base, fnftId, "&chainId=", block.chainid.toString())
        );
    }

    function setTokenURI(uint, string memory _uri) external override {
        animation_base = _uri;
    }

    function getRenderTokenURI(uint, address)
        external
        view
        override
        returns (string memory baseRenderURI, string[] memory parameters)
    {
        string[] memory arr;
        return (renderURI, arr);
    }

    function setRenderTokenURI(uint, string memory baseRenderURI) external override {
        renderURI = baseRenderURI;
    }

    function generateMetadata(address controller, uint fnftId) external view returns (string memory output) {
        string memory properties = generateProperties(controller, fnftId);
        output = string(
            abi.encodePacked(
                '{"name":"Revest FNFT", \n "description":"This Financial Non-Fungible Token is part of the Revest Protocol", \n "image":"',
                renderFNFT(controller, fnftId),
                '", \n'
            )
        );
        output = string(abi.encodePacked(output, '"animation_type":"interactive", \n'));
        output = string(abi.encodePacked(output, properties, "\n"));
    }

    function generateProperties(address _controller, uint fnftId) private view returns (string memory output) {
        IController controller = IController(_controller);

        IRevest.FNFTConfig memory fnft = controller.getFNFT(fnftId);

        ILockManager lockManager = ILockManager(fnft.lockManager);

        bytes32 lockId = keccak256(abi.encode(fnftId, _controller));
        ILockManager.Lock memory lock = lockManager.getLock(lockId);

        output = string(abi.encodePacked('"properties":{ \n "asset_ticker": \"', getTicker(fnft.asset), "\",\n"));
        output = string(abi.encodePacked(output, '"handler":"', toAsciiString(fnft.handler), '",\n'));
        output = string(abi.encodePacked(output, '"nonce":"', fnft.nonce.toString(), '",\n'));

        output = string(abi.encodePacked(output, '"asset_name":"', getName(fnft.asset), '",\n'));
        output = string(abi.encodePacked(output, '"asset_address":"', toAsciiString(fnft.asset), '",\n'));
        output = string(
            abi.encodePacked(
                output, '"currentValue":"', amountToDecimal(controller.getValue(fnftId), fnft.asset), '",\n'
            )
        );

        uint256 depositAmount = controller.getValue(fnftId);

        output = string(abi.encodePacked(output, '"amount":"', amountToDecimal(depositAmount, fnft.asset), '",\n'));
        output = string(abi.encodePacked(output, '"lock_type":"', getLockType(lockManager.lockType()), '",\n'));

        if (lockManager.lockType() == ILockManager.LockType.TimeLock) {


            // Handle time lock encoding
            output = string(
                abi.encodePacked(output, '"time_lock":{ \n "maturity_date":', lock.timeLockExpiry.toString(), ",\n ")
            );

            output = string(abi.encodePacked(output, '"maturity_extensions":', boolToString(fnft.maturityExtension), "\n }, \n"));

        } else if (lockManager.lockType() == ILockManager.LockType.AddressLock) {
            // Handle address lock encoding
            output = string(
                abi.encodePacked(
                    output, '"address_lock":{ \n "unlock_address":"', toAsciiString(address(lockManager)), '",'
                )
            );

            output =
                string(abi.encodePacked(output, '"address_metadata":"', string(lockManager.getMetadata(lockId)), '"'));

            output = string(abi.encodePacked(output, "\n},\n"));
        }


        output = string(abi.encodePacked(output, '"fnft_id":', fnftId.toString(), ",\n"));

        output = string(abi.encodePacked(output, '"network":', block.chainid.toString(), "\n } \n }"));
        // output = string(abi.encodePacked(output, '"image":', renderFNFT(_controller, fnftSalt), "\n }"));
    }

    function renderFNFT(address revest, uint fnftId) internal view returns (string memory) {
        IRevest.FNFTConfig memory config = IRevest(revest).getFNFT(fnftId);

        string memory assetName = getName(config.asset);
        string memory assetSymbol = getTicker(config.asset);

        bytes32 lockId = IRevest(revest).fnftIdToLockId(fnftId);

        bool isUnlocked = ILockManager(config.lockManager).getLockMaturity(lockId, fnftId);
        console.log("is unlocked: %s", isUnlocked);

        ILockManager.LockType typeOfLock = ILockManager(config.lockManager).lockType();

        string memory lockType =
            string.concat("Lock Type: ", typeOfLock == ILockManager.LockType.TimeLock ? "Time" : "Address");

        string memory image =
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 480"> <style> .tokens { font: bold 30px sans-serif; } .fee { font: bold 26px sans-serif; } .amount { font: bold 26px sans-serif ; fill: ';

        {
            //Changes the Color of the Token Amount and Name to Green
            if (isUnlocked) image = string.concat(image, isUnlockedColor);
            else image = string.concat(image, isLockedColor);

            //Something Else?
            image = string.concat(
                image, "; } .underLine { font: normal 13px sans-serif; } .cls-1{fill: #ccc;} .cls-2{fill: "
            );
            if (isUnlocked) image = string.concat(image, isUnlockedColor);
            else image = string.concat(image, isLockedColor);

            image = string.concat(
                image,
                ';} .cls-3{fill: #e4a238} .interest { font: bold 12px sans-serif; } .tick { font: normal 18px sans-serif; } .button { fill: #007bbf; pointer: cursor; } .button:hover { fill: #0069d9; } </style> <rect width="300" height="480" fill="hsl(0,0%,100%)" /> <rect x="30" y="30" width="240" height="388.32" rx="15" ry="15" fill="hsl(0,0%,18%)" stroke="#000" />'
            );

            // The Little Icon in the top-right Corner
            if (typeOfLock == ILockManager.LockType.TimeLock) {
                image = string.concat(
                    image,
                    '<svg id="Default" width = "15" x = "81%" y= "-190" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 576"><defs><style></style></defs><path class="cls-1" d="M306,108C147.09,108,18,237.09,18,396S147.09,684,306,684,594,554.91,594,396,464.91,108,306,108Zm0,521.6C177.1,629.6,72.4,524.9,72.4,396S177.1,162.4,306,162.4,539.6,267.1,539.6,396,434.9,629.6,306,629.6Z" transform="translate(-18 -108)"/><path class="cls-1" d="M419.75,469,334.8,384.07V223.2a28.8,28.8,0,0,0-57.6,0V396a28.75,28.75,0,0,0,8.44,20.36L379,509.75A28.8,28.8,0,0,0,419.75,469" transform="translate(-18 -108)"/></svg>'
                );
            } else {
                image = string.concat(
                    image,
                    '<svg id="Default" width = "15" x = "81%" y= "-190" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 576"><defs><style></style></defs><path class="cls-2" d="M449.42,254.32l-.51-.51" transform="translate(-18 -108)"/><path class="cls-1" d="M306,108C147.09,108,18,237.09,18,396S147.09,684,306,684,594,554.91,594,396,464.91,108,306,108Zm0,521.6C177.1,629.6,72.4,524.9,72.4,396S177.1,162.4,306,162.4,539.6,267.1,539.6,396,434.9,629.6,306,629.6Z" transform="translate(-18 -108)"/><path class="cls-1" d="M226.14,416.62l-87.57,95.31a203.68,203.68,0,0,1-30.43-164.15l118,68.84" transform="translate(-18 -108)"/><path class="cls-1" d="M159.84,537.8l95.63-104.08L306,463.2l50.53-29.48L452.16,537.8a203.62,203.62,0,0,1-292.32,0" transform="translate(-18 -108)"/><path class="cls-1" d="M473.43,511.93l-87.57-95.31,118-68.84a203.68,203.68,0,0,1-30.43,164.15" transform="translate(-18 -108)"/><path class="cls-1" d="M118.88,315.64,306,424.8,493.12,315.64a203.64,203.64,0,0,0-374.24,0" transform="translate(-18 -108)"/></svg>'
                );
            }

            //The Flip-Over Icon
            image = string.concat(
                image,
                '<svg xmlns="http://www.w3.org/2000/svg"  width = "15" x = "14%" y= "-190" viewBox="0 0 1000 1000" enable-background="new 0 0 1000 1000" xml:space="preserve" class="cls-3"> <g><path d="M174,535.4c-23.5-147,57.2-295.5,201.4-351.7c106.8-41.7,222-21.7,303.6,37.8L609.6,334l311.3-1.2L809.6,10l-57,92.3C632.4,24.5,468.6-1,325.1,54.9C126.4,132.4,12,332.8,34.5,535.4H174L174,535.4z"/><path d="M826.1,455c23.5,147-57.2,295.5-201.4,351.7c-98.3,38.3-206.6,23.9-289.9-27.8c15.9-25.7,62.7-101.6,62.7-101.6L62.8,657.6L204.5,990l59.4-96.2c120.2,77.8,267.6,97.6,411,41.7C873.6,858,988,657.6,965.5,455L826.1,455L826.1,455z"/></g> </svg>'
            );

            //The Circle around the lock
            image = string.concat(
                image,
                '<svg width = "200" x = "50" y = "-80" id="Default" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576.01 575.06"> <defs> <style>.cls-2</style> </defs> <path class="cls-2" d="M287.62,676a4.72,4.72,0,0,0-4.33-4.7C135.92,659.1,24.4,532.85,30.49,385.11S158.13,120.73,306,120.73,575.42,237.36,581.51,385.11s-105.43,274-252.8,286.17a4.72,4.72,0,0,0-4.33,4.7v2.84a4.74,4.74,0,0,0,1.52,3.46,4.68,4.68,0,0,0,3.58,1.23c154-12.59,270.59-144.43,264.28-298.79S460.49,108.47,306,108.47,24.54,230.36,18.24,384.72s110.31,286.2,264.28,298.79a4.71,4.71,0,0,0,5.1-4.69V676" transform="translate(-18 -108.47)"/> </svg>'
            );

            // This Controls the center Lock Image Itself
            if (isUnlocked) {
                image = string.concat(
                    image,
                    '<svg width = "40" x = "130" y = "-80" id="Default" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 615.77"><defs><style></style></defs><path class="cls-2" d="M182.57,662.74a41.18,41.18,0,0,0,41.14,41.15H552.86A41.18,41.18,0,0,0,594,662.74V457a41.17,41.17,0,0,0-41.14-41.14H223.71A41.17,41.17,0,0,0,182.57,457V662.74" transform="translate(-18 -88.11)"/><path class="cls-2" d="M244.29,374.74H306V232.11a144,144,0,0,0-288,0V333.6H79.71V232.11a82.29,82.29,0,0,1,164.58,0V374.74" transform="translate(-18 -88.11)"/></svg>'
                );
            } else {
                image = string.concat(
                    image,
                    '<svg width = "30" x = "135"   y = "-80" id="Default" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 549.88 768"><defs><style></style></defs><path class="cls-2" d="M196,340.1H113.54V204.46C113.54,98.26,199.8,12,306,12S498.46,98.26,498.46,204.46V340.1H416V204.46a110,110,0,0,0-220,0V340.1" transform="translate(-31.06 -12)"/><path class="cls-2" d="M31.06,725a55,55,0,0,0,55,55H526a55,55,0,0,0,55-55V450.07a55,55,0,0,0-55-55H86.05a55,55,0,0,0-55,55V725" transform="translate(-31.06 -12)"/></svg>'
                );
            }

            //Displays the camera bevel around the lock
            image = string.concat(
                image,
                '<svg width = "180" version="1.1" id="Default" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="60px" y="-80" viewBox="0 0 514.7 514.7" style="enable-background:new 0 0 514.7 514.7;" xml:space="preserve"> <style type="text/css"> .st0{fill:#7d7d7d;} </style> <path class="st0" d="M0.7,276.9c-6.3-83,27.9-163.9,91.8-217.2l142.2,82.1L0.7,276.9"/> <path class="st0" d="M146,489.4c-75-36-128-106.1-142.2-188.2L146,219.1V489.4"/> <path class="st0" d="M112.1,44.9c68.7-47,155.9-57.8,234-29.1V180L112.1,44.9"/> <path class="st0" d="M368.8,25.4c75,36,128,106.1,142.2,188.1l-142.2,82.1V25.4"/> <path class="st0" d="M514,237.8c6.3,83-27.9,163.9-91.8,217.2L280,372.9L514,237.8"/> <path class="st0" d="M402.6,469.8c-68.7,47-155.9,57.8-234,29.1V334.7L402.6,469.8"/> </svg>'
            );

            image = string.concat(
                image, '<text x="50%" y="310" dominant-baseline="middle" text-anchor="middle" class="fee" fill="#fff">'
            );

            image = string.concat(image, getName(config.asset));
            image = string.concat(
                image,
                '</text> <text x="50%" y="310" dy= "30" dominant-baseline="middle" text-anchor="middle" class="amount" fill="#fff"> '
            );
        }
        uint256 depositAmount;
        {
            depositAmount = IRevest(revest).getValue(fnftId);
            image = string.concat(
                image, amountToDecimal(depositAmount, config.asset), " ", getTicker(config.asset), "</text>"
            );

            image = string.concat(image, ILockManager(config.lockManager).lockDescription(lockId));

            image = string.concat(image, "</svg>");
        }

        // string memory description =
            renderDescription(assetName, assetSymbol, depositAmount, lockType, config.lockManager);

        string memory json = 
            Base64.encode(bytes(image));

        return string.concat("data:image/svg+xml;base64,", json);
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
            ", Amount: ",
            Strings.toHexString(amount),
            ", Receiver: ",
            Strings.toHexString(uint256(uint160(unlockAddress)), 20)
        );
    }

    //TODO: Implement as SVG
    function getImage(address, bytes32) public returns (string memory image) {
        //TODO: Implement as SVG
        image = "https://revest.mypinata.cloud/ipfs/QmW8BHSTMzV892N6i9qT79QC45MftxrvDti7JDHD56BS38";
    }

    function boolToString(bool arg) private pure returns (string memory boolean) {
        boolean = arg ? "true" : "false";
    }

    function getTicker(address asset) private view returns (string memory ticker) {
        try IERC20Metadata(asset).symbol() returns (string memory tick) {
            ticker = tick;
        } catch {
            ticker = "???";
        }
    }

    function getName(address asset) private view returns (string memory ticker) {
        try IERC20Metadata(asset).name() returns (string memory tick) {
            ticker = tick;
        } catch {
            ticker = "Unknown Token";
        }
    }

    function getDecimals(address asset) private view returns (string memory decStr) {
        uint8 decimals;
        try IERC20Metadata(asset).decimals() returns (uint8 dec) {
            decimals = dec;
        } catch {
            decimals = 18;
        }
        decStr = decimalString(decimals, 0);
    }

    function getLockType(ILockManager.LockType lock) private pure returns (string memory lockType) {
        if (lock == ILockManager.LockType.TimeLock) {
            lockType = "Time";
        } else if (lock == ILockManager.LockType.AddressLock) {
            lockType = "Address";
        } else {
            lockType = "DEFAULT";
        }
    }

    function amountToDecimal(uint256 amt, address asset) private view returns (string memory decStr) {
        uint8 decimals;
        try IERC20Metadata(asset).decimals() returns (uint8 dec) {
            decimals = dec;
        } catch {
            decimals = 18;
        }
        decStr = decimalString(amt, decimals);
    }

    function toAsciiString(address x) public pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", s));
    }

    function bytes32ToLiteralString(bytes32 data) public pure returns (string memory result) {
        bytes memory temp = new bytes(65);
        uint256 count;

        for (uint256 i = 0; i < 32; i++) {
            bytes1 currentByte = bytes1(data << (i * 8));

            uint8 c1 = uint8(bytes1((currentByte << 4) >> 4));

            uint8 c2 = uint8(bytes1((currentByte >> 4)));

            if (c2 >= 0 && c2 <= 9) temp[++count] = bytes1(c2 + 48);
            else temp[++count] = bytes1(c2 + 87);

            if (c1 >= 0 && c1 <= 9) temp[++count] = bytes1(c1 + 48);
            else temp[++count] = bytes1(c1 + 87);
        }

        result = string(temp);
    }

    function char(bytes1 b) public pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function decimalString(uint256 number, uint8 decimals) private pure returns (string memory) {
        uint256 tenPowDecimals = 10 ** decimals;

        uint256 temp = number;
        uint8 digits;
        uint8 numSigfigs;
        while (temp != 0) {
            if (numSigfigs > 0) {
                // count all digits preceding least significant figure
                numSigfigs++;
            } else if (temp % 10 != 0) {
                numSigfigs++;
            }
            digits++;
            temp /= 10;
        }

        DecimalStringParams memory params;
        if ((digits - numSigfigs) >= decimals) {
            // no decimals, ensure we preserve all trailing zeros
            params.sigfigs = number / tenPowDecimals;
            params.sigfigIndex = digits - decimals;
            params.bufferLength = params.sigfigIndex;
        } else {
            // chop all trailing zeros for numbers with decimals
            params.sigfigs = number / (10 ** (digits - numSigfigs));
            if (tenPowDecimals > number) {
                // number is less tahn one
                // in this case, there may be leading zeros after the decimal place
                // that need to be added

                // offset leading zeros by two to account for leading '0.'
                params.zerosStartIndex = 2;
                params.zerosEndIndex = decimals - digits + 2;
                params.sigfigIndex = numSigfigs + params.zerosEndIndex;
                params.bufferLength = params.sigfigIndex;
                params.isLessThanOne = true;
            } else {
                // In this case, there are digits before and
                // after the decimal place
                params.sigfigIndex = numSigfigs + 1;
                params.decimalIndex = digits - decimals + 1;
            }
        }
        params.bufferLength = params.sigfigIndex;
        return generateDecimalString(params);
    }

    // With modifications, the below taken
    // from https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/NFTDescriptor.sol#L189-L231

    struct DecimalStringParams {
        // significant figures of decimal
        uint256 sigfigs;
        // length of decimal string
        uint8 bufferLength;
        // ending index for significant figures (funtion works backwards when copying sigfigs)
        uint8 sigfigIndex;
        // index of decimal place (0 if no decimal)
        uint8 decimalIndex;
        // start index for trailing/leading 0's for very small/large numbers
        uint8 zerosStartIndex;
        // end index for trailing/leading 0's for very small/large numbers
        uint8 zerosEndIndex;
        // true if decimal number is less than one
        bool isLessThanOne;
    }

    function generateDecimalString(DecimalStringParams memory params) private pure returns (string memory) {
        bytes memory buffer = new bytes(params.bufferLength);
        if (params.isLessThanOne) {
            buffer[0] = "0";
            buffer[1] = ".";
        }

        // add leading/trailing 0's
        for (uint256 zerosCursor = params.zerosStartIndex; zerosCursor < params.zerosEndIndex; zerosCursor++) {
            buffer[zerosCursor] = bytes1(uint8(48));
        }
        // add sigfigs
        while (params.sigfigs > 0) {
            if (params.decimalIndex > 0 && params.sigfigIndex == params.decimalIndex) {
                buffer[--params.sigfigIndex] = ".";
            }
            buffer[--params.sigfigIndex] = bytes1(uint8(uint256(48) + (params.sigfigs % 10)));
            params.sigfigs /= 10;
        }
        return string(buffer);
    }
}
