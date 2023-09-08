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
import "../../config/constants.sol";

/**
 * @title ChainlinkOracle
 * @author @antoncoding
 * @dev return base price, with {UNIT_DECIMAL} decimals in USD.
 * @notice should only be used for USD denominated aggregators (e.g. ETH/USD is valid while ETH/BTC is not)
 */
contract ChainlinkOracle is IOracle, BaseOracle {
    using SafeCastLib for uint256;

    struct AggregatorData {
        address addr;
        uint8 decimals;
        uint32 maxDelay;
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
     * @notice  get spot price of _base, denominated in USD.
     * @param _base base asset. for ETH/USD price, ETH is the base asset
     * @return price with {UNIT_DECIMALS} decimals
     */
    function getSpotPrice(address _base) external view returns (uint256) {
        if (stableAssets[_base]) {
            return UNIT;
        }
        (uint256 basePrice, uint8 baseDecimals) = _getSpotPriceFromAggregator(_base);
        return _toPriceWithUnitDecimals(basePrice, baseDecimals);
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
        // Since this oracle is USD-denominated, we can ignore the _quote asset. We keep it to conform to the IOracle interface.
        return _getPriceAtTimestamp(_base, _timestamp);
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
    function reportPrice(address _base, uint256 _timestamp, uint80 _baseRoundId) external {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (historicalPrices[_base][_timestamp].reportAt != 0) {
            revert OC_PriceReported();
        }

        (uint256 basePrice, uint8 baseDecimals) = _getLastPriceBeforeTimestamp(_base, _baseRoundId, _timestamp);
        uint256 price = _toPriceWithUnitDecimals(basePrice, baseDecimals);

        historicalPrices[_base][_timestamp] = HistoricalPrice(false, uint64(block.timestamp), price.safeCastTo128());

        emit HistoricalPriceSet(_base, _timestamp, price, false);
    }

    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev admin function to set aggregator address for an asset
     */
    function setAggregator(address _asset, address _aggregator, uint32 _maxDelay) external onlyOwner {
        uint8 decimals = IAggregatorV3(_aggregator).decimals();
        aggregators[_asset] = AggregatorData(_aggregator, decimals, _maxDelay);
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

        if (updatedAt == 0) {
            revert CL_PriceNotReported();
        }

        // If we're using the latest round, the next round's price may not have been set yet.
        // This means we'd always have to wait till the next round's price is set for this function to not revert.
        (,,, uint256 nextRoundUpdatedAt,) = IAggregatorV3(address(aggregator.addr)).getRoundData(_roundId + 1);
        if (nextRoundUpdatedAt <= _timestamp) revert CL_RoundIdTooSmall();

        return (uint256(answer), aggregator.decimals);
    }
}
