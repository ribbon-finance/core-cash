// SPDX-License-Identifier: MIT
// solhint-disable max-line-length

pragma solidity ^0.8.0;

import "../config/enums.sol";
import "../config/errors.sol";

/**
 * Token ID =
 *
 *  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
 *  | tokenType (24 bits) | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | reserved    (64 bits) |
 *  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
 *
 *
 * Barrier ID =
 *
 *  * -------------------- | ------------------------------ | --------------------- | --------------------- |
 *  | barrierPCT (16 bits) | observationFrequency (8 bits)  | triggerType (4 bits)  | exerciseType (4 bits) *
 *  * -------------------- | ------------------------------ | --------------------- | --------------------- |
 *
 *  barrierPCT: percentage of the barrier relative to initial spot price
 *  observationFrequency: frequency of barrier observations (ObservationFrequencyType)
 *  triggerType: trigger type of the barrier (BarrierTriggerType)
 *  exerciseType: exercise type of the barrier (BarrierExerciseType)
 *
 */

library TokenIdUtil {
    /**
     * @notice calculate ERC1155 token id for given option parameters. See table above for tokenId
     * @param tokenType TokenType enum
     * @param productId if of the product
     * @param expiry timestamp of option expiry
     * @param longStrike strike price of the long option, with 6 decimals
     * @param reserved either leveragePCT (ONLY PUTS) (and/or) barrierId, or strike price of the short (upper bond for call and lower bond for put) if this is a spread (6 decimals)
     * @return tokenId token id
     */
    function getTokenId(TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike, uint64 reserved)
        internal
        pure
        returns (uint256 tokenId)
    {
        unchecked {
            tokenId = (uint256(tokenType) << 232) + (uint256(productId) << 192) + (uint256(expiry) << 128)
                + (uint256(longStrike) << 64) + uint256(reserved);
        }
    }

    /**
     * @notice derive option, product, expiry and strike price from ERC1155 token id
     * @dev    See table above for tokenId composition
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return productId 32 bits product id
     * @return expiry timestamp of option expiry
     * @return longStrike strike price of the long option, with 6 decimals
     * @return reserved either leveragePCT (and/or) barrierId, or strike price of the short (upper bond for call and lower bond for put) if this is a spread (6 decimals)
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
     * @notice derive reserve for non-spreads from reserve
     * @param reserve reserve
     * @return leveragePCT leveragef actor
     * @return barrierId barrier id
     */
    function parseReserve(uint64 reserve) internal pure returns (uint32 leveragePCT, uint32 barrierId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            leveragePCT := shr(32, reserve)
            barrierId := reserve
        }
    }

    /**
     * @notice calculate reserve
     * @param leveragePCT leverage factor
     * @param barrierId barrier id
     * @return reserve reserve
     */
    function getReserve(uint32 leveragePCT, uint32 barrierId) internal pure returns (uint64 reserve) {
        unchecked {
            reserve = (uint64(leveragePCT) << 32) + uint64(barrierId);
        }
    }

    /**
     * @notice calculate barrier id. See table above for barrier Id
     * @param barrierPCT percentage of the barrier relative to initial spot price
     * @param observationFrequency frequency of barrier observations
     * @param triggerType trigger type of the barrier
     * @param exerciseType exercise type of the barrier
     * @return barrierId barrier id
     */
    function getBarrierId(
        uint16 barrierPCT,
        BarrierObservationFrequencyType observationFrequency,
        BarrierTriggerType triggerType,
        BarrierExerciseType exerciseType
    ) internal pure returns (uint32 barrierId) {
        unchecked {
            barrierId = (uint32(barrierPCT) << 16) + (uint32(observationFrequency) << 8) + (uint32(triggerType) << 4)
                + uint32(exerciseType);
        }
    }

    /**
     * @notice derive barrierPCT, observationFrequency, barrierType, exerciseType from barrierId
     * @param barrierId barrier id
     * @return barrierPCT percentage of the barrier relative to initial spot price
     * @return observationFrequency frequency of barrier observations
     * @return triggerType trigger type of the barrier
     * @return exerciseType exercise type of the barrier
     */
    function parseBarrierId(uint32 barrierId)
        internal
        pure
        returns (
            uint16 barrierPCT,
            BarrierObservationFrequencyType observationFrequency,
            BarrierTriggerType triggerType,
            BarrierExerciseType exerciseType
        )
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            barrierPCT := shr(16, barrierId)
            observationFrequency := shr(8, barrierId)
            triggerType := barrierId
            triggerType := shr(4, triggerType) // shift >> 4 to wipe out exerciseType
            exerciseType := barrierId
            exerciseType := shl(4, exerciseType) // shift << 4 to wipe out triggerType
            exerciseType := shr(4, exerciseType) // shift >> 4 to go back
        }
    }

    /**
     * @notice derive frequency denominated in seconds
     * @param frequency barrier observation frequency type
     * @return frequency denominated in seconds
     */
    function convertBarrierObservationFrequencyType(BarrierObservationFrequencyType frequency) internal pure returns (uint256) {
        if (frequency == BarrierObservationFrequencyType.ONE_DAY) {
            return (1 days);
        } else if (frequency == BarrierObservationFrequencyType.ONE_WEEK) {
            return (7 days);
        } else if (frequency == BarrierObservationFrequencyType.TWO_WEEKS) {
            return (14 days);
        } else if (frequency == BarrierObservationFrequencyType.ONE_MONTH) {
            return (30 days);
        } else if (frequency == BarrierObservationFrequencyType.TWO_MONTHS) {
            return (60 days);
        } else if (frequency == BarrierObservationFrequencyType.THREE_MONTHS) {
            return (90 days);
        } else if (frequency == BarrierObservationFrequencyType.SIX_MONTHS) {
            return (180 days);
        } else if (frequency == BarrierObservationFrequencyType.NINE_MONTHS) {
            return (270 days);
        } else if (frequency == BarrierObservationFrequencyType.ONE_YEAR) {
            return (365 days);
        } else {
            return 1;
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

    /**
     * @notice convert an spread tokenId back to put or call.
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | ----------------------------------------------*
     * @dev   oldId =   | spread type (24 b)  | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | shortStrike (64 bits)                         |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | ----------------------------------------------*
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | ----------------------------------------------*
     * @dev   newId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | leveragePCT (32 bits) + barrierId (32 bits)|
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | ----------------------------------------------*
     * @dev   this function will: override tokenType, remove shortStrike.
     * @param _tokenId token id to change
     * @param _leveragePCT leveragePCT to add
     */
    function convertToVanillaId(uint256 _tokenId, uint256 _leveragePCT, uint256 _barrierID)
        internal
        pure
        returns (uint256 newId)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            newId := shr(64, _tokenId) // step 1: >> 64 to wipe out shortStrike
            newId := shl(64, newId) // step 2: << 64 go back

            newId := add(newId, shl(32, _leveragePCT)) // step 3: leveragePCT = _leveragePCT

            if sgt(_barrierID, 0) { newId := add(newId, _barrierID) } // step 4: barrierId = __barrierID

            newId := sub(newId, shl(232, 1)) // step 5: new tokenType = spread type - 1
        }
    }

    /**
     * @notice convert an spread tokenId back to put or call.
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   oldId =   | call or put type    | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | 0           (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     * @dev   newId =   | spread type         | productId (40 bits) | expiry (64 bits) | longStrike (64 bits) | shortStrike (64 bits) |
     *                  * ------------------- | ------------------- | ---------------- | -------------------- | --------------------- *
     *
     * this function convert put or call type to spread type, add shortStrike.
     * @param _tokenId token id to change
     * @param _shortStrike strike to add
     */
    function convertToSpreadId(uint256 _tokenId, uint256 _shortStrike) internal pure returns (uint256 newId) {
        // solhint-disable-next-line no-inline-assembly
        unchecked {
            newId = _tokenId + _shortStrike;
            return newId + (1 << 232); // new type (spread type) = old type + 1
        }
    }
}
