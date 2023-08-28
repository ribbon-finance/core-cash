// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracle} from "./PythOracle.sol";

import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// constants and types
import "./errors.sol";
import "../../config/constants.sol";

/**
 * @title PythOracleDisputable
 * @dev return base / quote price, with 6 decimals
 */
contract PythOracleDisputable is PythOracle {
    using SafeCastLib for uint256;

    // asset => dispute period
    mapping(address => uint256) public disputePeriod;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event DisputePeriodUpdated(address asset, uint256 period);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth) PythOracle(_owner, _pyth) {}

    /*///////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev return the maximum dispute period for the oracle
     */
    function maxDisputePeriod() external pure override returns (uint256) {
        return MAX_DISPUTE_PERIOD;
    }

    /**
     * @dev view function to check if dispute period is over
     */
    function isPriceFinalized(address _asset, uint256 _timestamp) external view returns (bool) {
        return _isPriceFinalized(_asset, _timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev dispute a reported price from the owner. Cannot dispute an un-reported price
     * @param _asset the address of the asset
     * @param _timestamp timestamp
     * @param _newPrice new price to set
     */
    function disputePrice(address _asset, uint256 _timestamp, uint256 _newPrice) external onlyOwner {
        if (stableAssets[_asset] == true) revert PY_CannotDisputeStableAsset();
        HistoricalPrice memory entry = historicalPrices[_asset][_timestamp];
        if (entry.reportAt == 0) revert OC_PriceNotReported();

        if (entry.reportAt + disputePeriod[_asset] < block.timestamp) revert OC_DisputePeriodOver();

        historicalPrices[_asset][_timestamp] = HistoricalPrice(true, uint64(block.timestamp), _newPrice.safeCastTo128());

        emit HistoricalPriceSet(_asset, _timestamp, _newPrice, true);
    }

    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev set the dispute period for a specific base / quote asset
     * @param _asset the address of the asset
     * @param _period dispute period. Cannot be set to a value longer than 365 days
     */
    function setDisputePeriod(address _asset, uint256 _period) external onlyOwner {
        if (_period > MAX_DISPUTE_PERIOD) revert OC_InvalidDisputePeriod();

        disputePeriod[_asset] = _period;

        emit DisputePeriodUpdated(_asset, _period);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev overrides _isExpiryPriceFinalized() from PythOracle to check if dispute period is over
     *      if true, getPriceAtTimestamp will return (price, true)
     */
    function _isPriceFinalized(address _asset, uint256 _timestamp) internal view override returns (bool) {
        if (stableAssets[_asset] == true) return true;
        HistoricalPrice memory entry = historicalPrices[_asset][_timestamp];
        if (entry.reportAt == 0) return false;

        if (entry.isDisputed) return true;

        return block.timestamp > entry.reportAt + disputePeriod[_asset];
    }
}
