// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// interfaces
import {IOracle} from "../../interfaces/IOracle.sol";

// constants and types
import "./errors.sol";
import "../../config/constants.sol";

/**
 * @title PythOracle
 * @dev return base / quote price, with 6 decimals
 */
contract PythOracle is IOracle, Ownable {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /// @notice 0x4305FB66699C3B2702D4d05CF36551390A4c69C6. https://docs.pyth.network/documentation/pythnet-price-feeds/evm.
    IPyth public immutable pyth;

    struct HistoricalPrice {
        bool isDisputed;
        uint64 reportAt;
        uint128 price;
    }

    // asset => timestamp => price.
    mapping(address => mapping(uint256 => HistoricalPrice)) internal historicalPrices;

    // pyth price feed IDs (https://pyth.network/developers/price-feed-ids) => asset
    mapping(bytes32 => address) public priceFeedIds;

    mapping(address => bool) public stableAssets;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event HistoricalPriceSet(address asset, uint256 timestamp, uint256 price, bool isDispute);

    event PriceFeedIDUpdated(bytes32 id, address asset);

    event PythUpdated(address newPyth);

    event StableAssetUpdated(address asset, bool isStableAsset);

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
     * @param _base base asset. for ETH/USDC price, ETH is the base asset
     * @param _quote quote asset. for ETH/USDC price, USDC is the quote asset
     * @param _timestamp timestamp to check
     * @return price with {UNIT_DECIMALS} decimals
     * @return isFinalized bool checking if dispute period is over
     */
    function getPriceAtTimestamp(address _base, address _quote, uint256 _timestamp)
        external
        view
        returns (uint256 price, bool isFinalized)
    {
        return _getPriceAtTimestamp(_base, _quote, _timestamp);
    }

    /**
     * @dev return the maximum dispute period for the oracle
     * @dev this oracle has no dispute mechanism, as long as a price is reported, it can be used to settle.
     */
    function maxDisputePeriod() external view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice report pyth price at a timestamp and write to storage
     * @notice Since pyth price feeds are USD denominated, stored prices are always coverted to {UNIT_DECIMALS} decimals
     * @dev anyone can call this function and set the price for a given timestamp
     */
    function reportPrice(bytes[] calldata _pythUpdateData, bytes32[] calldata priceIds, uint64 _timestamp)
        external payable
    {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        uint updateFee = pyth.getUpdateFee(_pythUpdateData);
        PythStructs.PriceFeed[] memory priceFeeds = pyth.parsePriceFeedUpdates{value: updateFee}(_pythUpdateData, priceIds, _timestamp, _timestamp);
        for (uint i = 0; i < priceFeeds.length; i++) {
            bytes32 id = priceFeeds[i].id;
            address asset = priceFeedIds[id];
            if (asset == address(0)) revert PY_AssetPriceFeedNotSet();
            int64 basePrice = priceFeeds[i].price.price;
            if (basePrice < 0) revert PY_NegativeBasePrice();
            uint256 positiveBasePrice = uint64(basePrice);
            int32 baseExpo = priceFeeds[i].price.expo;
            uint8 decimals;
            if (baseExpo < 0) {
                if (baseExpo < -255) revert PY_ExpoOutOfRange();
                decimals = uint8(uint32(-baseExpo));
            } else {
                decimals = 0;
                positiveBasePrice = positiveBasePrice * (10 ** uint32(baseExpo));
            }
            uint publishTime = priceFeeds[i].price.publishTime;
            if (publishTime != _timestamp) revert PY_DifferentPublishProvidedTimestamps();
            if (historicalPrices[asset][_timestamp].reportAt != 0) revert OC_PriceReported();
            uint256 price = _toPriceWithUnitDecimals(positiveBasePrice, UNIT, decimals, UNIT_DECIMALS);
            historicalPrices[asset][_timestamp] = HistoricalPrice(false, uint64(block.timestamp), price.safeCastTo128());
            emit HistoricalPriceSet(asset, _timestamp, price, false);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/


    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev set the pyth price feed ID for an asset
     * @param _id the bytes 32 ID of the price feed
     * @param _asset the address of the asset
     */
    function setPriceFeedID(bytes32 _id, address _asset) external onlyOwner {
        if (_id == bytes32(0)) revert PY_InvalidPriceFeedID();
        if (_asset == address(0)) revert OC_ZeroAddress();

        address currentAsset = priceFeedIds[_id];
        if (currentAsset == _asset) revert OC_ValueUnchanged();

        priceFeedIds[_id] = _asset;

        emit PriceFeedIDUpdated(_id, _asset);
    }

    /**
     * @dev sets a stable asset for this oracle
     * @param _asset the address of the asset
     * @param _isStableAsset boolean of if the asset is a stable asset
     */
    function setStableAsset(address _asset, bool _isStableAsset) external onlyOwner {
        if (_asset == address(0)) revert OC_ZeroAddress();
        bool currentIsStableAsset = stableAssets[_asset];
        if (currentIsStableAsset == _isStableAsset) revert OC_ValueUnchanged();
        stableAssets[_asset] = _isStableAsset;
        emit StableAssetUpdated(_asset, _isStableAsset);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

        /**
     * @dev get price of underlying at a particular timestamp, denominated in strike asset.
     *         can revert if timestamp is in the future, or the price has not been reported yet
     * @param _base base asset. for ETH/USDC price, ETH is the base asset
     * @param _quote quote asset. for ETH/USDC price, USDC is the quote asset
     * @param _timestamp timestamp to check
     * @return price with {UNIT_DECIMALS} decimals
     * @return isFinalized bool checking if dispute period is over
     */
    function _getPriceAtTimestamp(address _base, address _quote, uint256 _timestamp)
        internal
        view
        returns (uint256 price, bool isFinalized)
    {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        HistoricalPrice memory baseData = historicalPrices[_base][_timestamp];
        bool isBasePriceFinalized = _isPriceFinalized(_base, _timestamp);
        if (baseData.reportAt == 0) revert OC_PriceNotReported();
        if (stableAssets[_quote] == true) {
            return (baseData.price, isBasePriceFinalized);
        } else {
            HistoricalPrice memory quoteData = historicalPrices[_quote][_timestamp];
            if (quoteData.reportAt == 0) revert OC_PriceNotReported();
            uint256 convertedPrice = _toPriceWithUnitDecimals(baseData.price, quoteData.price, UNIT_DECIMALS, UNIT_DECIMALS);
            bool areBothAssetsFinalized = _isPriceFinalized(_quote, _timestamp) && isBasePriceFinalized;
            return (convertedPrice, areBothAssetsFinalized);
        }
    }

    /**
     * @dev this oracle has no dispute mechanism, so always return true.
     *      a un-reported price should have reverted at this point.
     */
    function _isPriceFinalized(address, uint256) internal view virtual returns (bool) {
        return true;
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
