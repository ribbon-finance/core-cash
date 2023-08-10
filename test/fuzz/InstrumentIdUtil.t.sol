// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {InstrumentIdUtil} from "../../src/libraries/InstrumentIdUtil.sol";

import "../../src/config/types.sol";
import "../../src/config/enums.sol";

contract InstrumentIdUtilTest is Test {
    mapping(uint256 => bool) public instrumentRegistered;

    function testInstrumentIdHigherThan0(Instrument calldata instrument) public {
        vm.assume(instrument.options[0] > 0);

        uint256 id = InstrumentIdUtil.getInstrumentId(instrument);

        assertGt(id, 0);
    }

    function testInstrumentIdUnique(Instrument calldata instrument) public {
        vm.assume(instrument.options[0] > 0);

        uint256 id = InstrumentIdUtil.getInstrumentId(instrument);

        assertEq(instrumentRegistered[id], false);
        instrumentRegistered[id] = true;
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

    function testCouponIdFormatAndParseAreMirrored(
        uint16 couponPCT,
        uint16 numInstallements,
        CouponType couponType,
        uint32 barrierId
    ) public {
        uint64 id = InstrumentIdUtil.getCouponId(couponPCT, numInstallements, couponType, barrierId);
        (uint16 _couponPCT, uint16 _numInstallements, CouponType _couponType, uint32 _barrierId) =
            InstrumentIdUtil.parseCouponId(id);

        assertEq(couponPCT, _couponPCT);
        assertEq(numInstallements, _numInstallements);
        assertEq(uint8(couponType), uint8(_couponType));
        assertEq(barrierId, _barrierId);
    }

    function testCouponIdGetAndParseAreMirrored(
        uint256 couponPCT,
        uint256 numInstallements,
        CouponType couponType,
        uint256 barrierId
    ) public {
        uint64 id = InstrumentIdUtil.getCouponId(uint16(couponPCT), uint16(numInstallements), couponType, uint32(barrierId));
        (uint16 _couponPCT, uint16 _numInstallements, CouponType _couponType, uint32 _barrierId) =
            InstrumentIdUtil.parseCouponId(id);

        assertEq(uint16(couponPCT), _couponPCT);
        assertEq(uint16(numInstallements), _numInstallements);
        assertEq(uint8(couponType), uint8(_couponType));
        assertEq(uint32(barrierId), _barrierId);
    }

    function testCouponsGetAndParseAreMirrored(uint64[] calldata coupons) public {
        uint256 len = coupons.length;
        vm.assume(len > 0);

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
}