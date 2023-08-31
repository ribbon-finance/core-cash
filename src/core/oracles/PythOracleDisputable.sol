// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracle} from "./PythOracle.sol";

// abstract
import {BaseOracle} from "./abstract/BaseOracle.sol";
import {DisputableOracle} from "./abstract/DisputableOracle.sol";

// constants and types
import "./errors.sol";
import "../../config/constants.sol";

/**
 * @title PythOracleDisputable
 * @dev pyth oracle that can be dispute by the owner
 */
contract PythOracleDisputable is PythOracle, DisputableOracle {
    constructor(address _owner, address _pyth, bytes32[] memory _initialFeedIds, address[] memory _initialBaseAddresses)
        PythOracle(_owner, _pyth, _initialFeedIds, _initialBaseAddresses)
    {}

    /**
     * @dev this function is intended to be overridden and should remain "view".
     */
    function maxDisputePeriod() external view override(PythOracle, DisputableOracle) returns (uint256) {
        return MAX_DISPUTE_PERIOD;
    }

    /**
     * @dev checks if dispute period is over
     *      if true, getPriceAtTimestamp will return (price, true)
     */
    function _isPriceFinalized(address _base, uint256 _timestamp)
        internal
        view
        override(BaseOracle, DisputableOracle)
        returns (bool)
    {
        if (stableAssets[_base]) {
            return true;
        }
        if (disputePeriod[_base] == 0) revert OC_DisputePeriodNotSet();
        HistoricalPrice memory entry = historicalPrices[_base][_timestamp];
        if (entry.reportAt == 0) return false;

        if (entry.isDisputed) return true;

        return block.timestamp > entry.reportAt + disputePeriod[_base];
    }
}
