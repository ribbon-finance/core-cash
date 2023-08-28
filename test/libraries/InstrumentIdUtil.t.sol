// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {InstrumentIdUtil} from "../../src/libraries/InstrumentIdUtil.sol";
import {TokenIdUtil} from "../../src/libraries/TokenIdUtil.sol";

import "../../src/config/constants.sol";
import "../../src/config/enums.sol";
import "../../src/config/errors.sol";
import "../../src/config/types.sol";

/**
 * @dev tester contract to make coverage works
 */
contract InstrumentIdUtilTester {
    function getExpiry(Instrument memory _instrument) external view returns (uint64) {
        uint64 result = InstrumentIdUtil.getExpiry(_instrument);
        return result;
    }

    function convertBarrierObservationFrequencyType(BarrierObservationFrequencyType frequency) external pure returns (uint256) {
        uint256 result = InstrumentIdUtil.convertBarrierObservationFrequencyType(frequency);
        return result;
    }
}

/**
 * Tests to improve coverage
 */
contract InstrumentIdLibTest is Test {
    uint256 public constant base = UNIT;

    InstrumentIdUtilTester tester;
    InstrumentIdUtil.InstrumentExtended internal instrument;
    uint32 internal barrierId;
    uint64 internal expiry;
    uint256 internal tokenId;

    function setUp() public {
        tester = new InstrumentIdUtilTester();
        instrument.oracleId = 1;
        instrument.engineId = 1;
        instrument.period = 1;
        expiry = 100;
        tokenId = TokenIdUtil.getTokenId(TokenType(1), 1, expiry, 3, 4);
        InstrumentIdUtil.Barrier memory barrier = InstrumentIdUtil.Barrier(
            uint16(1), BarrierObservationFrequencyType(uint8(2)), BarrierTriggerType(uint8(2)), BarrierExerciseType(uint8(2))
        );
        barrierId = InstrumentIdUtil.getBarrierId(
            barrier.barrierPCT, barrier.observationFrequency, barrier.triggerType, barrier.exerciseType
        );

        instrument.autocall = InstrumentIdUtil.Autocall(true, barrier);
        instrument.coupons.push(InstrumentIdUtil.Coupon(5, 6, CouponType(uint8(3)), barrier));
        instrument.options.push(InstrumentIdUtil.OptionExtended(5, barrier, tokenId));
    }

    function testSerialize() public {
        Instrument memory sInstrument = InstrumentIdUtil.serialize(instrument);

        assertEq(sInstrument.oracleId, 1);
        assertEq(sInstrument.engineId, 1);
        assertEq(sInstrument.autocallId, InstrumentIdUtil.getAutocallId(true, barrierId));
        assertEq(sInstrument.period, 1);

        uint64[] memory coupons = new uint64[](1);

        coupons[0] = InstrumentIdUtil.getCouponId(5, 6, CouponType(uint8(3)), barrierId);

        assertEq(sInstrument.coupons, InstrumentIdUtil.getCoupons(coupons));
        assertEq(sInstrument.options[0].participationPCT, 5);
        assertEq(sInstrument.options[0].barrierId, barrierId);
        assertEq(sInstrument.options[0].tokenId, tokenId);
    }

    function testConvertBarrierObservationFrequencyType() public {
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_DAY), 1 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_WEEK), 7 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.TWO_WEEKS), 14 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_MONTH), 30 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.TWO_MONTHS), 60 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.THREE_MONTHS), 90 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.SIX_MONTHS), 180 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.NINE_MONTHS), 270 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_YEAR), 365 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.NONE), 1);
    }

    function testExpiry() public {
        Instrument memory sInstrument = InstrumentIdUtil.serialize(instrument);
        assertEq(tester.getExpiry(sInstrument), expiry);
    }
}
