// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

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

    // asset => timestamp => price.
    mapping(address => mapping(uint256 => HistoricalPrice)) public historicalPrices;

    // asset => dispute period
    mapping(address => uint256) public disputePeriod;

    // pyth price feed IDs (https://pyth.network/developers/price-feed-ids) => asset
    mapping(bytes32 => address) public priceFeedIds;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event HistoricalPriceSet(address asset, uint256 timestamp, uint256 price, bool isDispute);

    event DisputePeriodUpdated(address asset, uint256 period);

    event PriceFeedIDUpdated(bytes32 id, address asset);

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
        // TODO need to do internal conversion from base to quote
        // HistoricalPrice memory data = historicalPrices[_base][_quote][_timestamp];
        // if (data.reportAt == 0) revert OC_PriceNotReported();

        // return (data.price, _isPriceFinalized(_base, _quote, _timestamp));
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
    function isPriceFinalized(address _asset, uint256 _timestamp) external view returns (bool) {
        return _isPriceFinalized(_asset, _timestamp);
    }

    /**
     * @notice report pyth price at a timestamp and write to storage
     * @dev anyone can call this function and set the price for a given timestamp
     */
    function reportPrice(bytes[] calldata _pythUpdateData, bytes32[] calldata priceIds, uint256 _timestamp)
        external payable
    {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (historicalPrices[_base][_quote][_timestamp].reportAt != 0) revert OC_PriceReported();
        uint updateFee = pyth.getUpdateFee(_pythUpdateData);
        PythStructs.PriceFeed[] memory priceFeeds = pyth.parsePriceFeedUpdates{value: updateFee}(_pythUpdateData, priceIds, _timestamp);

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
     * @param _asset the address of the asset
     * @param _timestamp timestamp
     * @param _newPrice new price to set
     */
    function disputePrice(address _asset, uint256 _timestamp, uint256 _newPrice) external onlyOwner {
        // TODO can't dispute stable asset price
        HistoricalPrice memory entry = historicalPrices[_asset][_timestamp];
        if (entry.reportAt == 0) revert OC_PriceNotReported();

        if (entry.reportAt + disputePeriod[_asset] < block.timestamp) revert OC_DisputePeriodOver();

        historicalPrices[_asset][_timestamp] = HistoricalPrice(true, uint64(block.timestamp), _newPrice.safeCastTo128());

        emit HistoricalPriceSet(_asset, _timestamp, _newPrice, true);
    }

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

    /**
     * @dev set the pyth price feed ID for an asset
     * @param _asset the address of the asset
     * @param _id the bytes 32 ID of the price feed
     */
    function setPriceFeedID(address _asset, bytes32 _id) external onlyOwner {
        if (_asset == address(0)) revert OC_ZeroAddress();
        if (_id == bytes32(0)) revert PY_InvalidPriceFeedID();

        bytes32 currentAsset = priceFeedIds[_id];
        if (currentAsset == _asset) revert OC_ValueUnchanged();

        priceFeedIds[_id] = _asset;

        emit PriceFeedIDUpdated(_id, _asset);
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
    function _isPriceFinalized(address _asset, uint256 _timestamp) internal view override returns (bool) {
        // TODO if stable asset always return true
        HistoricalPrice memory entry = historicalPrices[_asset][_timestamp];
        if (entry.reportAt == 0) return false;

        if (entry.isDisputed) return true;

        return block.timestamp > entry.reportAt + disputePeriod[_asset];
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
