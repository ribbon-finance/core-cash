// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {InstrumentIdUtil} from "../../src/libraries/InstrumentIdUtil.sol";

import "../../src/config/types.sol";
import "../../src/config/enums.sol";
import "../../src/config/constants.sol";

contract InstrumentIdUtilTest is Test {
    mapping(uint256 => bool) public instrumentRegistered;

    function testInstrumentIdHigherThan0(Instrument calldata instrument) public {
        vm.assume(instrument.options.length > 0);

        uint256 id = InstrumentIdUtil.getInstrumentId(instrument);

        assertGt(id, 0);
    }

    function testInstrumentIdUnique(Instrument calldata instrument) public {
        vm.assume(instrument.options.length > 0);

        uint256 id = InstrumentIdUtil.getInstrumentId(instrument);

        assertEq(instrumentRegistered[id], false);
        instrumentRegistered[id] = true;
    }

    function testBarrierIdHigherThan0(uint16 barrierPCT, uint8 observationFrequency, uint8 triggerType) public {
        vm.assume(barrierPCT > 0 || observationFrequency > 0 || triggerType > 0);
        vm.assume(observationFrequency <= uint8(type(BarrierObservationFrequencyType).max));
        vm.assume(triggerType <= uint8(type(BarrierTriggerType).max));

        uint256 id = InstrumentIdUtil.getBarrierId(
            barrierPCT, BarrierObservationFrequencyType(observationFrequency), BarrierTriggerType(triggerType)
        );

        assertGt(id, 0);
    }

    function testAutocallIdFormatAndParseAreMirrored(bool isReverse, uint32 barrierId) public {
        uint40 id = InstrumentIdUtil.getAutocallId(isReverse, barrierId);
        (bool _isReverse, uint32 _barrierId) = InstrumentIdUtil.parseAutocallId(id);

        assertEq(isReverse, _isReverse);
        assertEq(barrierId, _barrierId);
    }

    function testAutocallIdGetAndParseAreMirrored(bool isReverse, uint256 barrierId) public {
        uint40 id = InstrumentIdUtil.getAutocallId(isReverse, uint32(barrierId));
        (bool _isReverse, uint32 _barrierId) = InstrumentIdUtil.parseAutocallId(id);

        assertEq(isReverse, _isReverse);
        assertEq(uint32(barrierId), _barrierId);
    }

    function testCouponIdFormatAndParseAreMirrored(uint16 couponPCT, uint16 numInstallements, uint8 couponType, uint32 barrierId)
        public
    {
        vm.assume(numInstallements < 4096);
        vm.assume(couponType <= uint8(type(CouponType).max));

        uint64 id = InstrumentIdUtil.getCouponId(couponPCT, numInstallements, CouponType(couponType), barrierId);
        (uint16 _couponPCT, uint16 _numInstallements, CouponType _couponType, uint32 _barrierId) =
            InstrumentIdUtil.parseCouponId(id);

        assertEq(couponPCT, _couponPCT);
        assertEq(numInstallements, _numInstallements);
        assertEq(uint8(couponType), uint8(_couponType));
        assertEq(barrierId, _barrierId);
    }

    function testCouponIdGetAndParseAreMirrored(uint256 couponPCT, uint256 numInstallements, uint8 couponType, uint256 barrierId)
        public
    {
        vm.assume(numInstallements < 4096);
        vm.assume(couponType <= uint8(type(CouponType).max));

        uint64 id =
            InstrumentIdUtil.getCouponId(uint16(couponPCT), uint16(numInstallements), CouponType(couponType), uint32(barrierId));
        (uint16 _couponPCT, uint16 _numInstallements, CouponType _couponType, uint32 _barrierId) =
            InstrumentIdUtil.parseCouponId(id);

        assertEq(uint16(couponPCT), _couponPCT);
        assertEq(uint16(numInstallements), _numInstallements);
        assertEq(uint8(couponType), uint8(_couponType));
        assertEq(uint32(barrierId), _barrierId);
    }

    function testCouponsGetAndParseAreMirrored(uint64[] calldata coupons) public {
        uint256 len = coupons.length;

        vm.assume(len <= MAX_COUPON_CONSTRUCTION);

        for (uint256 i = 0; i < len; i++) {
            vm.assume(((coupons[i] >> 36) & ((1 << 13) - 1)) < 4096);
            vm.assume(((coupons[i] >> 32) & ((1 << 5) - 1)) <= uint8(type(CouponType).max));
        }

        uint256 _coupons = InstrumentIdUtil.getCoupons(coupons);

        for (uint256 i = 0; i < len; i++) {
            (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId) =
                InstrumentIdUtil.parseCouponId(_coupons, i);

            (uint16 _couponPCT, uint16 _numInstallements, CouponType _couponType, uint32 _barrierId) =
                InstrumentIdUtil.parseCouponId(coupons[i]);

            assertEq(couponPCT, _couponPCT);
            assertEq(numInstallements, _numInstallements);
            assertEq(uint8(couponType), uint8(_couponType));
            assertEq(barrierId, _barrierId);
        }
    }

    function testBarrierIdFormatAndParseAreMirrored(uint16 barrierPCT, uint8 observationFrequency, uint8 triggerType) public {
        vm.assume(observationFrequency <= uint8(type(BarrierObservationFrequencyType).max));
        vm.assume(triggerType <= uint8(type(BarrierTriggerType).max));

        uint32 id = InstrumentIdUtil.getBarrierId(
            barrierPCT, BarrierObservationFrequencyType(observationFrequency), BarrierTriggerType(triggerType)
        );

        (uint16 _barrierPCT, BarrierObservationFrequencyType _observationFrequency, BarrierTriggerType _triggerType) =
            InstrumentIdUtil.parseBarrierId(id);

        assertEq(barrierPCT, _barrierPCT);
        assertEq(uint8(observationFrequency), uint8(_observationFrequency));
        assertEq(uint8(triggerType), uint8(_triggerType));
    }

    function testBarrierIdGetAndParseAreMirrored(uint256 barrierPCT, uint8 observationFrequency, uint8 triggerType) public {
        vm.assume(observationFrequency <= uint8(type(BarrierObservationFrequencyType).max));
        vm.assume(triggerType <= uint8(type(BarrierTriggerType).max));

        uint32 id = InstrumentIdUtil.getBarrierId(
            uint16(barrierPCT), BarrierObservationFrequencyType(observationFrequency), BarrierTriggerType(triggerType)
        );
        (uint16 _barrierPCT, BarrierObservationFrequencyType _observationFrequency, BarrierTriggerType _triggerType) =
            InstrumentIdUtil.parseBarrierId(id);

        assertEq(uint16(barrierPCT), _barrierPCT);
        assertEq(observationFrequency, uint8(_observationFrequency));
        assertEq(triggerType, uint8(_triggerType));
    }
}
