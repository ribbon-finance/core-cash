// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ChainlinkOracle} from "./ChainlinkOracle.sol";

// abstract
import {BaseOracle} from "./abstract/BaseOracle.sol";
import {DisputableOracle} from "./abstract/DisputableOracle.sol";

// constants and types
import "../../config/constants.sol";

/**
 * @title ChainlinkOracleDisputable
 * @author antoncoding
 * @dev chainlink oracle that can be dispute by the owner
 */
contract ChainlinkOracleDisputable is ChainlinkOracle, DisputableOracle {
    constructor(address _owner) ChainlinkOracle(_owner) {}

    /**
     * @dev return the maximum dispute period for the oracle
     */
    function maxDisputePeriod() external view override(ChainlinkOracle, DisputableOracle) returns (uint256) {
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
