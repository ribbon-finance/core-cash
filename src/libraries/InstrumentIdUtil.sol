// SPDX-License-Identifier: MIT
// solhint-disable max-line-length

pragma solidity ^0.8.0;

import "../config/enums.sol";
import "../config/errors.sol";
import "../config/constants.sol";
import "../config/types.sol";

import "./TokenIdUtil.sol";

/**
 *
 *
 * Instrument ID = KECCAK256(struct Instrument)
 *
 * Instrument (368 bits + 256 bits * MAX_OPTION_CONSTRUCTION) =
 *
 *  * ------------------ | ---------------- | -------------------- | ------------------- | --------------------------------------------- |
 *  | engineId (8 bits)  | period (64 bits) | autocallId (40 bits) | coupons (256 bits)  | options (512 bits * MAX_OPTION_CONSTRUCTION)  *
 *  *------------------- | ---------------- | -------------------- | ------------------- | --------------------------------------------- |
 *
 *  engineId: id of the engine
 *  period: duration of instrument
 *  autocallId: id of the autocall
 *  coupons: packed coupons
 *  options: array of options
 *
 * Autocall ID (40 bits total) =
 *
 *  * -------------------- |
 *  | barrierId (32 bits)  *
 *  * -------------------- |
 *
 *  barrierId: id of the autocallable barrier
 *
 * Coupons (256 bits total) =
 *
 *  * ------------------- | ------------------- | ------------------- | ------------------- |
 *  | coupon (64 bits)    | coupon (64 bits)    | coupon (64 bits)    | coupon (64 bits)    *
 *  * ------------------- | ------------------- | ------------------- | ------------------- |
 *
 * Coupon ID (64 bits total) =
 *
 *  * ------------------- | ---------------------- | -------------------- | -------------------- |
 *  | couponPCT (16 bits) | isPartitioned (8 bits) | couponType (8 bits)  | barrierId (32 bits)  *
 *  * ------------------- | ---------------------- | -------------------- | -------------------- |
 *
 *  couponPCT: coupon percentage of notional
 *  isPartitioned: whether coupons broken up into installments (ONLY AUTOCALL COUPONS)
 *  couponType: coupon type (!NONE ONLY AUTOCALL COUPONS)
 *  barrierId: id of the barrier
 *
 *
 * Barrier ID (32 bits total) =
 *
 *  * -------------------- | ------------------------------ | --------------------- |
 *  | barrierPCT (16 bits) | observationFrequency (8 bits)  | triggerType (8 bits)  |
 *  * -------------------- | ------------------------------ | --------------------- |
 *
 *  barrierPCT: percentage of the barrier relative to initial spot price in {UNIT_PERCENTAGE_DECIMALS} decimals
 *  observationFrequency: frequency of barrier observations (ObservationFrequencyType)
 *  triggerType: trigger type of the barrier (BarrierTriggerType)
 *
 */

library InstrumentIdUtil {
    struct InstrumentExtended {
        uint64 period;
        uint8 engineId;
        Barrier autocall;
        Coupon[] coupons;
        OptionExtended[] options;
    }

    struct Coupon {
        uint16 couponPCT;
        uint8 isPartitioned;
        CouponType couponType;
        Barrier barrier;
    }

    struct OptionExtended {
        uint16 participationPCT;
        Barrier barrier;
        uint256 token;
    }

    struct Barrier {
        uint16 barrierPCT;
        BarrierObservationFrequencyType observationFrequency;
        BarrierTriggerType triggerType;
    }

    /**
     * @notice serialize instrument
     * @param _instrument InstrumentExtended struct
     * @return instrument
     */
    function serialize(InstrumentExtended memory _instrument) internal pure returns (Instrument memory) {
        return Instrument(
            _instrument.period,
            _instrument.engineId,
            serializeAutocall(_instrument.autocall),
            serializeCoupons(_instrument.coupons),
            serializeOptions(_instrument.options)
        );
    }

    /**
     * @notice calculate ERC1155 token id for given instrument parameters.
     * @param _instrument Instrument struct
     * @return instrumentId id of the instrument
     */
    function getInstrumentId(Instrument memory _instrument) internal pure returns (uint256 instrumentId) {
        bytes32 start =
            keccak256(abi.encode(_instrument.period, _instrument.engineId, _instrument.autocallId, _instrument.coupons));

        Option[] memory options = _instrument.options;
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
     * @notice calculate ERC1155 token id for given instrument parameters.
     * @param _instrument InstrumentExtended struct
     * @return instrumentId id of the instrument
     */
    function getInstrumentId(InstrumentExtended memory _instrument) internal pure returns (uint256 instrumentId) {
        return getInstrumentId(serialize(_instrument));
    }

    /**
     * @notice calculate coupons packing. See table above for coupons
     * @param couponArr array of coupons
     * @return coupons coupons
     */
    function getCoupons(uint64[] memory couponArr) internal pure returns (uint256 coupons) {
        for (uint256 i = 0; i < couponArr.length; i++) {
            coupons = coupons + (uint256(couponArr[i]) << (64 * (MAX_COUPON_CONSTRUCTION - i - 1)));
        }
    }

    /**
     * @notice calculate coupon id. See table above for couponId
     * @param couponPCT coupon percentage of notional
     * @param isPartitioned whether coupon is partitioned
     * @param couponType coupon type
     * @param barrierId barrier id
     * @return couponId coupon id
     */
    function getCouponId(uint16 couponPCT, uint8 isPartitioned, CouponType couponType, uint32 barrierId)
        internal
        pure
        returns (uint64 couponId)
    {
        unchecked {
            couponId = (uint64(couponPCT) << 48) + (uint64(isPartitioned) << 40) + (uint64(couponType) << 32) + uint64(barrierId);
        }
    }

    /**
     * @notice derive couponPCT, isPartitioned, couponType, barrierId from coupon packing
     * @param coupons coupons
     * @param index of the coupon (max 4)
     * @return couponPCT coupon percentage of notional
     * @return isPartitioned whether coupon is partitioned
     * @return couponType coupon type
     * @return barrierId barrier id
     */
    function parseCouponId(uint256 coupons, uint256 index)
        internal
        pure
        returns (uint16 couponPCT, uint8 isPartitioned, CouponType couponType, uint32 barrierId)
    {
        uint64 couponId;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            couponId := shr(mul(sub(MAX_COUPON_CONSTRUCTION, add(index, 1)), 64), coupons)
        }

        (couponPCT, isPartitioned, couponType, barrierId) = parseCouponId(couponId);
    }

    /**
     * @notice derive couponPCT, isPartitioned, couponType, barrierId from couponId
     * @param couponId coupon id
     * @return couponPCT coupon percentage of notional
     * @return isPartitioned whether coupon is partitioned
     * @return couponType coupon type
     * @return barrierId barrier id
     */
    function parseCouponId(uint64 couponId)
        internal
        pure
        returns (uint16 couponPCT, uint8 isPartitioned, CouponType couponType, uint32 barrierId)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            couponPCT := shr(48, couponId)
            isPartitioned := and(shr(40, couponId), 0xFF)
            couponType := and(shr(32, couponId), 0xFF)
            barrierId := couponId
        }
    }

    /**
     * @notice calculate barrier id. See table above for barrier Id
     * @param barrierPCT percentage of the barrier relative to initial spot price in {UNIT_PERCENTAGE_DECIMALS} decimals
     * @param observationFrequency frequency of barrier observations
     * @param triggerType trigger type of the barrier
     * @return barrierId barrier id
     */
    function getBarrierId(uint16 barrierPCT, BarrierObservationFrequencyType observationFrequency, BarrierTriggerType triggerType)
        internal
        pure
        returns (uint32 barrierId)
    {
        unchecked {
            barrierId = (uint32(barrierPCT) << 16) + (uint32(observationFrequency) << 8) + uint32(triggerType);
        }
    }

    /**
     * @notice derive barrierPCT, observationFrequency, barrierType from barrierId
     * @param barrierId barrier id
     * @return barrierPCT percentage of the barrier relative to initial spot price in {UNIT_PERCENTAGE_DECIMALS} decimals
     * @return observationFrequency frequency of barrier observations
     * @return triggerType trigger type of the barrier
     */
    function parseBarrierId(uint32 barrierId)
        internal
        pure
        returns (uint16 barrierPCT, BarrierObservationFrequencyType observationFrequency, BarrierTriggerType triggerType)
    {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            barrierPCT := shr(16, barrierId)
            observationFrequency := and(shr(8, barrierId), 0xFF)
            triggerType := and(barrierId, 0xFF)
        }
    }

    /**
     * @notice derive frequency denominated in seconds
     * @param frequency barrier observation frequency type
     * @return frequency denominated in seconds
     */
    function getFrequency(BarrierObservationFrequencyType frequency) internal pure returns (uint256) {
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
     * @notice Derive barrier exercise type
     * @param frequency barrier observation frequency type
     * @return barrier exercise type
     */
    function getExerciseType(BarrierObservationFrequencyType frequency) internal pure returns (BarrierExerciseType) {
        if (frequency == BarrierObservationFrequencyType.NONE) {
            return BarrierExerciseType.EUROPEAN;
        } else if (frequency == BarrierObservationFrequencyType.ONE_SECOND) {
            return BarrierExerciseType.CONTINUOUS;
        } else {
            return BarrierExerciseType.DISCRETE;
        }
    }

    /**
     * @notice serialize autocall struct
     * @param _autocall Autocall struct
     * @return autocallId
     */
    function serializeAutocall(Barrier memory _autocall) private pure returns (uint32 autocallId) {
        autocallId = getBarrierId(_autocall.barrierPCT, _autocall.observationFrequency, _autocall.triggerType);
    }

    /**
     * @notice serialize coupons
     * @param _coupons Coupon struct array
     * @return coupons
     */
    function serializeCoupons(Coupon[] memory _coupons) private pure returns (uint256 coupons) {
        uint64[] memory couponsArr = new uint64[](MAX_COUPON_CONSTRUCTION);

        for (uint8 i; i < _coupons.length;) {
            Coupon memory coupon = _coupons[i];
            uint32 couponBarrierId =
                getBarrierId(coupon.barrier.barrierPCT, coupon.barrier.observationFrequency, coupon.barrier.triggerType);

            couponsArr[i] = getCouponId(coupon.couponPCT, coupon.isPartitioned, coupon.couponType, couponBarrierId);
            unchecked {
                ++i;
            }
        }

        coupons = getCoupons(couponsArr);
    }

    /**
     * @notice serialize options
     * @param _options OptionExtended struct array
     * @return options
     */
    function serializeOptions(OptionExtended[] memory _options) private pure returns (Option[] memory options) {
        options = new Option[](MAX_OPTION_CONSTRUCTION);

        for (uint8 i; i < _options.length;) {
            OptionExtended memory option = _options[i];
            uint32 optionBarrierId =
                getBarrierId(option.barrier.barrierPCT, option.barrier.observationFrequency, option.barrier.triggerType);

            options[i] = Option(option.participationPCT, optionBarrierId, option.token);
            unchecked {
                ++i;
            }
        }
    }
}
