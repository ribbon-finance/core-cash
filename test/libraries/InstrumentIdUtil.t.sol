// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {InstrumentIdUtil} from "../../src/libraries/InstrumentIdUtil.sol";
import "../../src/config/constants.sol";
import "../../src/config/errors.sol";
import "../../src/config/types.sol";

/**
 * @dev tester contract to make coverage works
 */
contract InstrumentIdUtilTester {
    function getFrequency(BarrierObservationFrequencyType frequency) external pure returns (uint256) {
        uint256 result = InstrumentIdUtil.getFrequency(frequency);
        return result;
    }

    function getExerciseType(BarrierObservationFrequencyType frequency) external pure returns (BarrierExerciseType) {
        BarrierExerciseType result = InstrumentIdUtil.getExerciseType(frequency);
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

    function setUp() public {
        tester = new InstrumentIdUtilTester();
        instrument.period = 1;
        instrument.engineId = 1;
        InstrumentIdUtil.Barrier memory barrier =
            InstrumentIdUtil.Barrier(uint16(1), BarrierObservationFrequencyType(uint8(2)), BarrierTriggerType(uint8(2)));
        barrierId = InstrumentIdUtil.getBarrierId(barrier.barrierPCT, barrier.observationFrequency, barrier.triggerType);

        instrument.autocall = InstrumentIdUtil.Autocall(true, barrier);
        instrument.coupons.push(InstrumentIdUtil.Coupon(5, 6, CouponType(uint8(3)), barrier));
        instrument.options.push(InstrumentIdUtil.OptionExtended(5, barrier, 1));
    }

    function testSerialize() public {
        Instrument memory sInstrument = InstrumentIdUtil.serialize(instrument);

        assertEq(sInstrument.period, 1);
        assertEq(sInstrument.engineId, 1);
        assertEq(sInstrument.autocallId, InstrumentIdUtil.getAutocallId(true, barrierId));

        uint64[] memory coupons = new uint64[](1);

        coupons[0] = InstrumentIdUtil.getCouponId(5, 6, CouponType(uint8(3)), barrierId);

        assertEq(sInstrument.coupons, InstrumentIdUtil.getCoupons(coupons));
        assertEq(sInstrument.options[0].participationPCT, 5);
        assertEq(sInstrument.options[0].barrierId, barrierId);
        assertEq(sInstrument.options[0].tokenId, 1);
    }

    function testGetFrequency() public {
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.ONE_DAY), 1 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.ONE_WEEK), 7 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.TWO_WEEKS), 14 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.ONE_MONTH), 30 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.TWO_MONTHS), 60 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.THREE_MONTHS), 90 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.SIX_MONTHS), 180 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.NINE_MONTHS), 270 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.ONE_YEAR), 365 days);
        assertEq(tester.getFrequency(BarrierObservationFrequencyType.NONE), 1);
    }

    function testGetExerciseType() public {
        assertEq(uint256(tester.getExerciseType(BarrierObservationFrequencyType.NONE)), uint256(BarrierExerciseType.EUROPEAN));
        assertEq(
            uint256(tester.getExerciseType(BarrierObservationFrequencyType.ONE_SECOND)), uint256(BarrierExerciseType.CONTINUOUS)
        );
        assertEq(uint256(tester.getExerciseType(BarrierObservationFrequencyType.ONE_DAY)), uint256(BarrierExerciseType.DISCRETE));
    }
}
