// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import {BaseOracle} from "./BaseOracle.sol";

// constants and types
import "../errors.sol";
import "../../../config/constants.sol";

/**
 * @title DisputableOracle
 * @author antoncoding
 * @dev oracle that can be disputed by the owner
 */
abstract contract DisputableOracle is BaseOracle {
    using SafeCastLib for uint256;

    // base => quote => dispute period
    mapping(address => mapping(address => uint256)) public disputePeriod;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event DisputePeriodUpdated(address base, address quote, uint256 period);

    /**
     * @dev return the maximum dispute period for the oracle
     */
    function maxDisputePeriod() external view virtual returns (uint256) {
        return MAX_DISPUTE_PERIOD;
    }

    /**
     * @dev dispute a reported price from the owner. Cannot dispute an un-reported price
     * @param _base base asset
     * @param _quote quote asset
     * @param _timestamp timestamp
     * @param _newPrice new price to set
     */
    function disputePrice(address _base, address _quote, uint256 _timestamp, uint256 _newPrice) external onlyOwner {
        HistoricalPrice memory entry = historicalPrices[_base][_quote][_timestamp];
        if (entry.reportAt == 0) revert OC_PriceNotReported();

        if (entry.isDisputed) revert OC_PriceDisputed();

        if (entry.reportAt + disputePeriod[_base][_quote] < block.timestamp) revert OC_DisputePeriodOver();

        historicalPrices[_base][_quote][_timestamp] = HistoricalPrice(true, uint64(block.timestamp), _newPrice.safeCastTo128());

        emit HistoricalPriceSet(_base, _quote, _timestamp, _newPrice, true);
    }

    /**
     * @dev owner can set a price if the the price has not been pushed for at least 36 hours
     * @param _base base asset
     * @param _quote quote asset
     * @param _timestamp timestamp
     * @param _price price to set
     */
    function setPriceBackup(address _base, address _quote, uint256 _timestamp, uint256 _price) external onlyOwner {
        HistoricalPrice memory entry = historicalPrices[_base][_quote][_timestamp];
        if (entry.reportAt != 0) revert OC_PriceReported();

        if (_timestamp + 36 hours > block.timestamp) revert OC_GracePeriodNotOver();

        historicalPrices[_base][_quote][_timestamp] = HistoricalPrice(true, uint64(block.timestamp), _price.safeCastTo128());

        emit HistoricalPriceSet(_base, _quote, _timestamp, _price, true);
    }

    /**
     * @dev set the dispute period for a specific base / quote asset
     * @param _base base asset
     * @param _quote quote asset
     * @param _period dispute period. Cannot be set to a value longer than 6 hours
     */
    function setDisputePeriod(address _base, address _quote, uint256 _period) external onlyOwner {
        if (_period > MAX_DISPUTE_PERIOD) revert OC_InvalidDisputePeriod();

        disputePeriod[_base][_quote] = _period;

        emit DisputePeriodUpdated(_base, _quote, _period);
    }

    /**
     * @dev checks if dispute period is over
     *      if true, getPriceAtTimestamp will return (price, true)
     */
    function _isPriceFinalized(address _base, address _quote, uint256 _timestamp) internal view virtual override returns (bool) {
        HistoricalPrice memory entry = historicalPrices[_base][_quote][_timestamp];
        if (entry.reportAt == 0) return false;

        if (entry.isDisputed) return true;

        return block.timestamp > entry.reportAt + disputePeriod[_base][_quote];
    }
}
