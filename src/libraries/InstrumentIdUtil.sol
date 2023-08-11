// SPDX-License-Identifier: MIT
// solhint-disable max-line-length

pragma solidity ^0.8.0;

import "../config/enums.sol";
import "../config/errors.sol";
import "../config/constants.sol";
import "../config/types.sol";

/**
 *
 *
 * Instrument ID = KECCAK256(struct Instrument)
 *
 * Instrument (296 bits + 256 bits * MAX_OPTION_CONSTRUCTION) =
 *
 *  * -------------------- | ------------------- | --------------------------------------------- |
 *  | autocallId (40 bits) | coupons (256 bits)  | options (512 bits * MAX_OPTION_CONSTRUCTION)  *
 *  * -------------------- | ------------------- | --------------------------------------------- |
 *
 *  autocallId: id of the autocall
 *  coupons: packed coupons
 *  options: array of options
 *
 * Autocall ID (40 bits total) =
 *
 *  * ------------------- | ------------------- |
 *  | isReverse (8 bits)  | barrierId (32 bits) *
 *  * ------------------- | ------------------- |
 *
 *  isReverse: whether it is a reverse autocallable
 *  barrierId: id of the barrier
 *
 * Coupons (256 bits total) =
 *
 *  * ------------------- | ------------------- | ------------------- | ------------------- |
 *  | coupon (64 bits)    | coupon (64 bits)    | coupon (64 bits)    | coupon (64 bits)    *
 *  * ------------------- | ------------------- | ------------------- | ------------------- |
 *
 * Coupon ID (64 bits total) =
 *
 *  * ------------------- | -------------------------- | -------------------- | -------------------- |
 *  | couponPCT (16 bits) | numInstallements (12 bits) | couponType (4 bits)  | barrierId (32 bits)  *
 *  * ------------------- | -------------------------- | -------------------- | -------------------- |
 *
 *  couponPCT: coupon percentage of notional
 *  numInstallements: number of coupon installments (ONLY AUTOCALL COUPONS)
 *  couponType: coupon type (!NONE ONLY AUTOCALL COUPONS)
 *  barrierId: id of the barrier
 *
 */

library InstrumentIdUtil {
    /**
     * @notice calculate ERC1155 token id for given instrument parameters.
     * @param instrument Instrument struct
     * @return instrumentId id of the instrument
     */
    function getInstrumentId(Instrument calldata instrument) internal pure returns (uint256 instrumentId) {
        bytes32 start = keccak256(abi.encode(instrument.autocallId, instrument.coupons));

        Option[] memory options = instrument.options;
        for (uint256 i = 0; i < options.length; i++) {
            Option memory option = options[i];

            if (option.allocationPCT == 0) {
                break;
            }

            start = keccak256(abi.encode(start, option.allocationPCT, option.tokenId));
        }

        instrumentId = uint256(start);
    }

    /**
     * @notice calculate autocall id. See table above for autocallId
     * @param isReverse whether it is a reverse autocallable
     * @param barrierId id of the barrier
     * @return autocallId autocall id
     */
    function getAutocallId(bool isReverse, uint32 barrierId) internal pure returns (uint40 autocallId) {
        unchecked {
            autocallId = (uint40((isReverse ? 1 : 0)) << 32) + uint40(barrierId);
        }
    }

    /**
     * @notice derive isReverse, barrierId from autocallId
     * @param autocallId autocall id
     * @return isReverse whether it is a reverse autocallable
     * @return barrierId id of the barrier
     */
    function parseAutocallId(uint40 autocallId) internal pure returns (bool isReverse, uint32 barrierId) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            isReverse := shr(32, autocallId)
            barrierId := autocallId
        }
    }

    /**
     * @notice calculate coupons packing. See table above for coupons
     * @param couponArr array of coupons
     * @return coupons coupons
     */
    function getCoupons(uint64[] calldata couponArr) internal pure returns (uint256 coupons) {
        for (uint256 i = 0; i < couponArr.length; i++) {
            coupons = coupons + (uint256(couponArr[i]) << (64 * (MAX_COUPON_CONSTRUCTION - i - 1)));
        }
    }

    /**
     * @notice calculate coupon id. See table above for couponId
     * @param couponPCT coupon percentage of notional
     * @param numInstallements number of installments
     * @param couponType coupon type
     * @param barrierId barrier id
     * @return couponId coupon id
     */
    function getCouponId(uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId)
        internal
        pure
        returns (uint64 couponId)
    {
        unchecked {
            couponId =
                (uint64(couponPCT) << 48) + (uint64(numInstallements) << 36) + (uint64(couponType) << 32) + uint64(barrierId);
        }
    }

    /**
     * @notice derive couponPCT, numInstallements, couponType, barrierId from coupon packing
     * @param coupons coupons
     * @param index of the coupon (max 4)
     * @return couponPCT coupon percentage of notional
     * @return numInstallements number of installments
     * @return couponType coupon type
     * @return barrierId barrier id
     */
    function parseCouponId(uint256 coupons, uint256 index)
        internal
        pure
        returns (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId)
    {
        uint64 couponId;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            couponId := shr(mul(sub(MAX_COUPON_CONSTRUCTION, add(index, 1)), 64), coupons)
        }

        (couponPCT, numInstallements, couponType, barrierId) = parseCouponId(couponId);
    }

    /**
     * @notice derive couponPCT, numInstallements, couponType, barrierId from couponId
     * @param couponId coupon id
     * @return couponPCT coupon percentage of notional
     * @return numInstallements number of installments
     * @return couponType coupon type
     * @return barrierId barrier id
     */
    function parseCouponId(uint64 couponId)
        internal
        pure
        returns (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            couponPCT := shr(48, couponId)
            numInstallements := and(shr(36, couponId), 0xFFF)
            couponType := and(shr(32, couponId), 0xF)
            barrierId := couponId
        }
    }
}
