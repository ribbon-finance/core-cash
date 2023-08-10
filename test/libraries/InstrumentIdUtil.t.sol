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
}
