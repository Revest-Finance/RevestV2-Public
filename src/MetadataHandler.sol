// SPDX-License-Identifier: GNU-GPL v3.0 or later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./interfaces/IMetadataHandler.sol";
import "./interfaces/ITokenVault.sol";
import "./interfaces/ILockManager.sol";
import "./interfaces/IRevest.sol";
import "./interfaces/ILockManager.sol";

contract MetadataHandler is IMetadataHandler {
    using ERC165Checker for address;
    using Strings for uint256;

    string public renderURI;
    string private animation_base;

    address public immutable tokenVault;

    constructor(address _tokenVault, string memory animBase) {
        animation_base = animBase;
        tokenVault = _tokenVault;
    }

    function getTokenURI(bytes32 fnftId) external view override returns (string memory) {
        return string(abi.encodePacked(animation_base, bytes32ToLiteralString(fnftId), "&chainId=", block.chainid.toString()));
    }

    function setTokenURI(bytes32, string memory _uri) external override {
        animation_base = _uri;
    }

    function getRenderTokenURI(bytes32, address)
        external
        view
        override
        returns (string memory baseRenderURI, string[] memory parameters)
    {
        string[] memory arr;
        return (renderURI, arr);
    }

    function setRenderTokenURI(bytes32, string memory baseRenderURI) external override {
        renderURI = baseRenderURI;
    }

    function generateMetadata(address controller, bytes32 fnftId) external view returns (string memory output) {
        string memory properties = generateProperties(controller, fnftId);
        output = string(
            abi.encodePacked(
                '{"name":"Revest FNFT", \n "description":"This Financial Non-Fungible Token is part of the Revest Protocol", \n "image":"',
                getImage(fnftId),
                '", \n'
            )
        );
        output = string(abi.encodePacked(output, properties, ",\n"));
        output = string(abi.encodePacked(output, '"animation_type":"interactive", \n "parameters":', properties));
    }

    function generateProperties(address _controller, bytes32 fnftSalt) private view returns (string memory output) {
        IController controller = IController(_controller);

        IRevest.FNFTConfig memory fnft = controller.getFNFT(fnftSalt);

        ILockManager lockManager = ILockManager(fnft.lockManager);

        ILockManager.Lock memory lock = lockManager.getLock(fnft.lockId);

        output = string(abi.encodePacked('"properties":{ \n "created":', lock.creationTime.toString(), ",\n"));
        output = string(abi.encodePacked(output, '"asset_ticker":"', getTicker(fnft.asset), '",\n'));
        output = string(abi.encodePacked(output, '"handler":"', toAsciiString(fnft.handler), '",\n'));
        output = string(abi.encodePacked(output, '"nonce":"', fnft.nonce.toString(), '",\n'));

        output = string(abi.encodePacked(output, '"asset_name":"', getName(fnft.asset), '",\n'));
        output = string(abi.encodePacked(output, '"asset_address":"', toAsciiString(fnft.asset), '",\n'));
        output = string(
            abi.encodePacked(
                output, '"currentValue":"', amountToDecimal(controller.getValue(fnftSalt), fnft.asset), '",\n'
            )
        );
        output = string(abi.encodePacked(output, '"amount":"', amountToDecimal(fnft.depositAmount, fnft.asset), '",\n'));
        output = string(abi.encodePacked(output, '"lock_type":"', getLockType(lockManager.lockType()), '",\n'));

        if (lockManager.lockType() == ILockManager.LockType.TimeLock) {
            // Handle time lock encoding
            output = string(
                abi.encodePacked(output, '"time_lock":{ \n "maturity_date":', lock.timeLockExpiry.toString(), "\n },\n")
            );
        } else if (lockManager.lockType() == ILockManager.LockType.AddressLock) {
            // Handle address lock encoding
            output = string(
                abi.encodePacked(
                    output, '"address_lock":{ \n "unlock_address":"', toAsciiString(address(lockManager)), '",'
                )
            );

            output = string(abi.encodePacked(output, '"address_metadata":"', string(lockManager.getMetadata()), '"'));

            output = string(abi.encodePacked(output, "\n},\n"));
        }

        output = string(abi.encodePacked(output, '"maturity_extensions":', boolToString(fnft.maturityExtension), ",\n"));
        output = string(abi.encodePacked(output, '"nontransferrable":', boolToString(fnft.nontransferrable), ",\n"));

        output = string(abi.encodePacked(output, '"salt":', bytes32ToLiteralString(fnftSalt), ",\n"));
        output = string(abi.encodePacked(output, '"fnft_id":', fnft.fnftId.toString(), ",\n"));


        //TODO: Removed Due to Output Receivers being deprecated
        // if(fnft.pipeToContract.supportsInterface(OUTPUT_RECEIVER_INTERFACE_ID)) ///See TokenVault.sol
        //     output = string(abi.encodePacked(output, '"output_metadata":"', string(IOutputReceiver(fnft.pipeToContract).getCustomMetadata(fnftId)),'",\n'));
        output = string(abi.encodePacked(output, '"network":', block.chainid.toString(), "\n }"));
    }

    function getImage(bytes32) private pure returns (string memory image) {
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
