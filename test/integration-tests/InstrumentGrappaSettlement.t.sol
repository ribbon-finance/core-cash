// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "./GrappaSettlement.t.sol";

/**
 * @dev test getPayout function on different token types
 */
contract InstrumentGrappaSettlementTest is GrappaSettlementTest, InstrumentGrappaSetup {
    function setUp() public override {
        _setupInstrumentGrappaTestEnvironment();
    }

    // TODO
    // settleInstrument()
    // getOptionPayout()
    // getCouponPayout()
    // getInstrumentPayout()
}
