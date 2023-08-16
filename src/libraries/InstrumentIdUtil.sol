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
 * Instrument (368 bits + 256 bits * MAX_OPTION_CONSTRUCTION) =
 *
 *  * ------------------ | --------------------------- | -------------------- | ------------------- | --------------------------------------------- |
 *  | engineId (8 bits)  | initialSpotPrice (64 bits)  | autocallId (40 bits) | coupons (256 bits)  | options (512 bits * MAX_OPTION_CONSTRUCTION)  *
 *  *------------------- | --------------------------- | -------------------- | ------------------- | --------------------------------------------- |
 *
 *  engineId: id of the engine
 *  initialSpotPrice: initial spot price at creation
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
 *
 * Barrier ID (32 bits total) =
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

library InstrumentIdUtil {
    /**
     * @notice calculate ERC1155 token id for given instrument parameters.
     * @param instrument Instrument struct
     * @return instrumentId id of the instrument
     */
    function getInstrumentId(Instrument calldata instrument) internal pure returns (uint256 instrumentId) {
        bytes32 start =
            keccak256(abi.encode(instrument.initialSpotPrice, instrument.engineId, instrument.autocallId, instrument.coupons));

        Option[] memory options = instrument.options;
        for (uint256 i = 0; i < options.length; i++) {
            Option memory option = options[i];

            if (option.participationPCT == 0) {
                break;
            }

            start = keccak256(abi.encode(start, option.participationPCT, option.barrierId, option.tokenId));
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
            observationFrequency := and(shr(8, barrierId), 0xFF)
            triggerType := and(shr(4, barrierId), 0xF)
            exerciseType := and(barrierId, 0xF)
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
}
