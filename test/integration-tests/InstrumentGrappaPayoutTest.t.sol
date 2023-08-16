// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "./GrappaPayoutTest.t.sol";

/**
 * @dev test getPayout function on different token types
 */
contract InstrumentGrappaPayoutTest is GrappaPayoutTest, InstrumentGrappaSetup {
    function setUp() public override {
        _setupInstrumentGrappaTestEnvironment();
    }

    // TODO
}
