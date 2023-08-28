// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// interfaces
import {IOracle} from "../../interfaces/IOracle.sol";
import {IAggregatorV3} from "../../interfaces/IAggregatorV3.sol";
// abstract
import {BaseOracle} from "./abstract/BaseOracle.sol";

// constants and types
import "./errors.sol";

/**
 * @title ChainlinkOracle
 * @author @antoncoding
 * @dev return base / quote price, with 6 decimals
 */
contract ChainlinkOracle is IOracle, BaseOracle {
    using SafeCastLib for uint256;

    struct AggregatorData {
        address addr;
        uint8 decimals;
        uint32 maxDelay;
        bool isStable; // answer of stable asset can be used as long as the answer is not stale
    }

    // asset => aggregator
    mapping(address => AggregatorData) public aggregators;

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) BaseOracle(_owner) {}

    /*///////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice  get spot price of _base, denominated in _quote.
     * @param _base base asset. for ETH/USD price, ETH is the base asset
     * @param _quote quote asset. for ETH/USD price, USD is the quote asset
     * @return price with 6 decimals
     */
    function getSpotPrice(address _base, address _quote) external view returns (uint256) {
        (uint256 basePrice, uint8 baseDecimals) = _getSpotPriceFromAggregator(_base);
        (uint256 quotePrice, uint8 quoteDecimals) = _getSpotPriceFromAggregator(_quote);
        return _toPriceWithUnitDecimals(basePrice, quotePrice, baseDecimals, quoteDecimals);
    }

    /**
     * @dev get price of underlying at a particular timestamp, denominated in strike asset.
     *         can revert if timestamp is in the future, or the price has not been reported by authorized party
     * @param _base base asset. for ETH/USD price, ETH is the base asset
     * @param _quote quote asset. for ETH/USD price, USD is the quote asset
     * @param _timestamp timestamp to check
     * @return price with 6 decimals
     */
    function getPriceAtTimestamp(address _base, address _quote, uint256 _timestamp)
        external
        view
        override
        returns (uint256 price, bool isFinalized)
    {
        return _getPriceAtTimestamp(_base, _quote, _timestamp);
    }

    /**
     * @dev return the maximum dispute period for the oracle
     * @dev this oracle has no dispute mechanism, as long as a price is reported, it can be used to settle.
     */
    function maxDisputePeriod() external view virtual override returns (uint256 disputePeriod) {
        return 0;
    }

    /**
     * @notice report price and write to storage
     * @dev anyone can call this function and freeze the price for a timestamp
     */
    function reportPrice(address _base, address _quote, uint256 _timestamp, uint80 _baseRoundId, uint80 _quoteRoundId) external {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (historicalPrices[_base][_quote][_timestamp].reportAt != 0) {
            revert OC_PriceReported();
        }

        (uint256 basePrice, uint8 baseDecimals) = _getLastPriceBeforeTimestamp(_base, _baseRoundId, _timestamp);
        (uint256 quotePrice, uint8 quoteDecimals) = _getLastPriceBeforeTimestamp(_quote, _quoteRoundId, _timestamp);
        uint256 price = _toPriceWithUnitDecimals(basePrice, quotePrice, baseDecimals, quoteDecimals);

        historicalPrices[_base][_quote][_timestamp] = HistoricalPrice(false, uint64(block.timestamp), price.safeCastTo128());

        emit HistoricalPriceSet(_base, _quote, _timestamp, price, false);
    }

    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev admin function to set aggregator address for an asset
     */
    function setAggregator(address _asset, address _aggregator, uint32 _maxDelay, bool _isStable) external onlyOwner {
        uint8 decimals = IAggregatorV3(_aggregator).decimals();
        aggregators[_asset] = AggregatorData(_aggregator, decimals, _maxDelay, _isStable);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev fetch price with their native decimals from Chainlink aggregator
     */
    function _getSpotPriceFromAggregator(address _asset) internal view returns (uint256 price, uint8 decimals) {
        AggregatorData memory aggregator = aggregators[_asset];
        if (aggregator.addr == address(0)) revert CL_AggregatorNotSet();

        // request answer from Chainlink
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(address(aggregator.addr)).latestRoundData();

        if (block.timestamp - updatedAt > aggregator.maxDelay) {
            revert CL_StaleAnswer();
        }

        return (uint256(answer), aggregator.decimals);
    }

    /**
     * @notice get the price from an roundId, and make sure it is the last price before specified timestamp
     * @param _asset asset to report
     * @param _roundId chainlink roundId that should be used
     * @param _timestamp timestamp to check
     */
    function _getLastPriceBeforeTimestamp(address _asset, uint80 _roundId, uint256 _timestamp)
        internal
        view
        returns (uint256 price, uint8 decimals)
    {
        AggregatorData memory aggregator = aggregators[_asset];
        if (aggregator.addr == address(0)) revert CL_AggregatorNotSet();

        // request answer from Chainlink
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(address(aggregator.addr)).getRoundData(_roundId);

        // if timestamp < updatedAt, this line will revert
        if (_timestamp - updatedAt > aggregator.maxDelay) {
            revert CL_StaleAnswer();
        }

        // it is not a stable asset: make sure timestamp of answer #(round + 1) is higher than provided timestamp
        if (!aggregator.isStable) {
            (,,, uint256 nextRoundUpdatedAt,) = IAggregatorV3(address(aggregator.addr)).getRoundData(_roundId + 1);
            if (nextRoundUpdatedAt <= _timestamp) revert CL_RoundIdTooSmall();
        }

        return (uint256(answer), aggregator.decimals);
    }
}
