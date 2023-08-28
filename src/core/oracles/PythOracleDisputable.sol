// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracle} from "./PythOracle.sol";

// abstract
import {BaseOracle} from "./abstract/BaseOracle.sol";
import {DisputableOracle} from "./abstract/DisputableOracle.sol";

// constants and types
import "../../config/constants.sol";

/**
 * @title PythOracleDisputable
 * @dev pyth oracle that can be dispute by the owner
 */
contract PythOracleDisputable is PythOracle, DisputableOracle {
    constructor(address _owner, address _pyth) PythOracle(_owner, _pyth) {}

    /**
     * @dev return the maximum dispute period for the oracle
     */
    function maxDisputePeriod() external view override(PythOracle, DisputableOracle) returns (uint256) {
        return MAX_DISPUTE_PERIOD;
    }

    /**
     * @dev checks if dispute period is over
     *      if true, getPriceAtTimestamp will return (price, true)
     */
    function _isPriceFinalized(address _base, address _quote, uint256 _timestamp)
        internal
        view
        override(BaseOracle, DisputableOracle)
        returns (bool)
    {
        HistoricalPrice memory entry = historicalPrices[_base][_quote][_timestamp];
        if (entry.reportAt == 0) return false;

        if (entry.isDisputed) return true;

        return block.timestamp > entry.reportAt + disputePeriod[_base][_quote];
    }
}
