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
    function getInstrumentId(Instrument calldata instrument) external pure returns (uint256 instrumentId) {
        uint256 result = InstrumentIdUtil.getInstrumentId(instrument);
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

    function setUp() public {
        tester = new InstrumentIdUtilTester();
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
}
