// SPDX-License-Identifier: MIT
// solhint-disable max-line-length

pragma solidity ^0.8.0;

import "../config/enums.sol";
import "../config/errors.sol";
import "../config/constants.sol";
import "../config/types.sol";

/**
 * Instrument ID = KECCAK256(struct Instrument)
 */

library InstrumentIdUtil {
    /**
     * @notice calculate ERC1155 token id for given instrument parameters.
     * @param instrument Instrument struct
     */
    function getInstrumentId(Instrument memory instrument) internal pure returns (uint256 tokenId) {
        bytes32 start = "";

        for (uint256 i = 0; i < MAX_OPTION_CONSTRUCTION; i++) {
            Option memory option = instrument.options[i];

            if (option.baseTokenId == 0) {
                break;
            }

            start = keccak256(abi.encode(start, option.baseTokenId, option.leverageFactor, option.barrierPCT, option.barrierId));
        }

        for (uint256 i = 0; i < MAX_COUPON_CONSTRUCTION; i++) {
            Coupon memory coupon = instrument.coupons[i];

            if (coupon.couponPCT == 0) {
                break;
            }

            start = keccak256(
                abi.encode(
                    start, coupon.couponPCT, coupon.numInstallements, coupon.couponType, coupon.barrierPCT, coupon.barrierId
                )
            );
        }

        Autocall memory autocall = instrument.autocall;
        tokenId = uint256(keccak256(abi.encode(start, autocall.isReverse, autocall.barrierPCT, autocall.barrierId)));
    }

    // Barrier Id first 32 bits are observationFrequency, second 4 are barrier type, third 4 are exercise type
    // function parseBarrierId(uint24 barrierId){};

    /**
     * @notice derive option, product, expiry and strike price from ERC1155 token id
     * @dev    See table above for tokenId composition
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return productId 32 bits product id
     * @return expiry timestamp of option expiry
     * @return longStrike strike price of the long option, with 6 decimals
     * @return reserved strike price of the short (upper bond for call and lower bond for put) if this is a spread. 6 decimals
     */
    function parseTokenId(uint256 tokenId)
        internal
        pure
        returns (TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike, uint64 reserved)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokenType := shr(232, tokenId)
            productId := shr(192, tokenId)
            expiry := shr(128, tokenId)
            longStrike := shr(64, tokenId)
            reserved := tokenId
        }
    }

    /**
     * @notice parse collateral id from tokenId
     * @dev more efficient than parsing tokenId and than parse productId
     * @param tokenId token id
     * @return collateralId
     */
    function parseCollateralId(uint256 tokenId) internal pure returns (uint8 collateralId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // collateralId is the last bits of productId
            collateralId := shr(192, tokenId)
        }
    }

    /**
     * @notice parse engine id from tokenId
     * @dev more efficient than parsing tokenId and than parse productId
     * @param tokenId token id
     * @return engineId
     */
    function parseEngineId(uint256 tokenId) internal pure returns (uint8 engineId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // collateralId is the last bits of productId
            engineId := shr(216, tokenId) // 192 to get product id, another 24 to get engineId
        }
    }

    /**
     * @notice derive option type from ERC1155 token id
     * @param tokenId token id
     * @return tokenType TokenType enum
     */
    function parseTokenType(uint256 tokenId) internal pure returns (TokenType tokenType) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokenType := shr(232, tokenId)
        }
    }

    /**
     * @notice derive if option is expired from ERC1155 token id
     * @param tokenId token id
     * @return expired bool
     */
    function isExpired(uint256 tokenId) internal view returns (bool expired) {
        uint64 expiry;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            expiry := shr(128, tokenId)
        }

        expired = block.timestamp >= expiry;
    }
}
