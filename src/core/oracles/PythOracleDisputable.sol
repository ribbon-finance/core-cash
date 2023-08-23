// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// interfaces
import {IOracle} from "../../interfaces/IOracle.sol";
import {IAggregatorV3} from "../../interfaces/IAggregatorV3.sol";

// constants and types
import "./errors.sol";
import "../../config/constants.sol";

/**
 * @title PythOracleDisputable
 * @dev return base / quote price, with 6 decimals
 */
contract PythOracleDisputable is IOracle, Ownable {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    IPyth public pyth;

    struct HistoricalPrice {
        bool isDisputed;
        uint64 reportAt;
        uint128 price;
    }

    // base => quote => timestamp => price.
    mapping(address => mapping(address => mapping(uint256 => HistoricalPrice))) public historicalPrices;

    // base => quote => dispute period
    mapping(address => mapping(address => uint256)) public disputePeriod;

    // asset => pyth price feed IDs (https://pyth.network/developers/price-feed-ids)
    mapping(address => bytes32) public priceFeedIds;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event HistoricalPriceSet(address base, address quote, uint256 timestamp, uint256 price, bool isDispute);

    event DisputePeriodUpdated(address base, address quote, uint256 period);

    event PriceFeedIDUpdated(address asset, bytes32 id);

    event PythUpdated(address newPyth);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth) {
        // solhint-disable-next-line reason-string
        if (_owner == address(0)) revert OC_ZeroAddress();
        if (_pyth == address(0)) revert OC_ZeroAddress();
        pyth = IPyth(_pyth);

        _transferOwnership(_owner);
    }

    /*///////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev get price of underlying at a particular timestamp, denominated in strike asset.
     *         can revert if timestamp is in the future, or the price has not been reported yet
     * @param _base base asset. for ETH/USD price, ETH is the base asset
     * @param _quote quote asset. for ETH/USD price, USD is the quote asset
     * @param _timestamp timestamp to check
     * @return price with 6 decimals
     */
    function getPriceAtTimestamp(address _base, address _quote, uint256 _timestamp)
        external
        view
        returns (uint256 price, bool isFinalized)
    {
        HistoricalPrice memory data = historicalPrices[_base][_quote][_timestamp];
        if (data.reportAt == 0) revert OC_PriceNotReported();

        return (data.price, _isPriceFinalized(_base, _quote, _timestamp));
    }

    /**
     * @dev return the maximum dispute period for the oracle
     */
    function maxDisputePeriod() external pure override returns (uint256) {
        return MAX_DISPUTE_PERIOD;
    }

    /**
     * @dev view function to check if dispute period is over
     */
    function isPriceFinalized(address _base, address _quote, uint256 _timestamp) external view returns (bool) {
        return _isPriceFinalized(_base, _quote, _timestamp);
    }

    /**
     * @notice report pyth price at a timestamp and write to storage
     * @dev anyone can call this function and set the price for a given timestamp
     */
    function reportPrice(address _base, address _quote, uint256 _timestamp, bytes[] calldata pythUpdateData)
        external
    {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (historicalPrices[_base][_quote][_timestamp].reportAt != 0) revert OC_PriceReported();

        (uint256 basePrice, uint8 baseDecimals) = _getLastPriceBeforeExpiry(_base, _baseRoundId, _timestamp);
        (uint256 quotePrice, uint8 quoteDecimals) = _getLastPriceBeforeExpiry(_quote, _quoteRoundId, _timestamp);
        uint256 price = _toPriceWithUnitDecimals(basePrice, quotePrice, baseDecimals, quoteDecimals);

        historicalPrices[_base][_quote][_timestamp] = HistoricalPrice(false, uint64(block.timestamp), price.safeCastTo128());

        emit HistoricalPriceSet(_base, _quote, _timestamp, price, false);
    }

    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

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

        if (entry.reportAt + disputePeriod[_base][_quote] < block.timestamp) revert OC_DisputePeriodOver();

        historicalPrices[_base][_quote][_timestamp] = HistoricalPrice(true, uint64(block.timestamp), _newPrice.safeCastTo128());

        emit HistoricalPriceSet(_base, _quote, _timestamp, _newPrice, true);
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
     * @dev set the pyth price feed ID for an asset
     * @param _asset the address of the asset
     * @param _id the bytes 32 ID of the price feed
     */
    function setPriceFeedID(address _asset, bytes32 _id) external onlyOwner {
        if (_asset == address(0)) revert OC_ZeroAddress();
        if (_id == bytes32(0)) revert PY_InvalidPriceFeedID();

        bytes32 currentID = priceFeedIds[_asset];
        if (currentID == _id) revert OC_ValueUnchanged();

        priceFeedIds[_asset] = _id;

        emit PriceFeedIDUpdated(_asset, _id);
    }

    /**
     * @dev set the pyth contract for this oracle
     * @param _pyth the address of the pyth contract
     */
    function setPyth(address _pyth) external onlyOwner {
        if (_pyth == address(0)) revert OC_ZeroAddress();
        pyth = IPyth(_pyth);
        emit PythUpdated(_pyth);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev checks if dispute period is over
     *      if true, getPriceAtTimestamp will return (price, true)
     */
    function _isPriceFinalized(address _base, address _quote, uint256 _timestamp) internal view override returns (bool) {
        HistoricalPrice memory entry = historicalPrices[_base][_quote][_timestamp];
        if (entry.reportAt == 0) return false;

        if (entry.isDisputed) return true;

        return block.timestamp > entry.reportAt + disputePeriod[_base][_quote];
    }

    /**
     * @notice  convert prices of base & quote asset to base / quote, denominated in UNIT
     * @param _basePrice price of base asset from aggregator
     * @param _quotePrice price of quote asset from aggregator
     * @param _baseDecimals decimals of _basePrice
     * @param _quoteDecimals decimals of _quotePrice
     * @return price base / quote price with {UNIT_DECIMALS} decimals
     */
    function _toPriceWithUnitDecimals(uint256 _basePrice, uint256 _quotePrice, uint8 _baseDecimals, uint8 _quoteDecimals)
        internal
        pure
        returns (uint256 price)
    {
        if (_baseDecimals == _quoteDecimals) {
            // .mul UNIT to make sure the final price has 6 decimals
            price = _basePrice.mulDivUp(UNIT, _quotePrice);
        } else {
            // we will return basePrice * 10^(baseMulDecimals) / quotePrice;
            int8 baseMulDecimals = int8(UNIT_DECIMALS) + int8(_quoteDecimals) - int8(_baseDecimals);
            if (baseMulDecimals > 0) {
                price = _basePrice.mulDivUp(10 ** uint8(baseMulDecimals), _quotePrice);
            } else {
                price = _basePrice / (_quotePrice * (10 ** uint8(-baseMulDecimals)));
            }
        }
    }
}
