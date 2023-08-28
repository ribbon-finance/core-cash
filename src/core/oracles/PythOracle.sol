// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// interfaces
import {IOracle} from "../../interfaces/IOracle.sol";
import {InstrumentOracle} from "./abstract/InstrumentOracle.sol";
import {IInstrumentGrappa} from "../../interfaces/IInstrumentGrappa.sol";

// constants and types
import "./errors.sol";
import "../../config/enums.sol";
import "../../config/types.sol";
import "../../config/constants.sol";

/**
 * @title PythOracle
 * @dev return base / quote price, with 6 decimals
 */
contract PythOracle is IOracle, InstrumentOracle, Ownable {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    IPyth public pyth;

    struct HistoricalPrice {
        bool isDisputed;
        uint64 reportAt;
        uint128 price;
    }

    // asset => timestamp => price.
    // NOTE: You should not access this mapping directly to get prices. Instead, use the getPriceAtTimestamp method to handle stable asset cases.
    // We leave it as public so the inheriting contracts can access this
    mapping(address => mapping(uint256 => HistoricalPrice)) public historicalPrices;

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

    constructor(address _owner, address _pyth, address _instrumentGrappaAddress) InstrumentOracle(_instrumentGrappaAddress) {
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

    function isBarrierBreached(uint256 _instrumentId, uint32 _barrierId) external override view returns (bool isBreached, bool isFinalized) {
        (uint16 barrierPCT, BarrierExerciseType exerciseType, uint64 period, uint64 expiry, address underlying, address strike) = _getBarrierInformation(_instrumentId, _barrierId);
        if (exerciseType == BarrierExerciseType.EUROPEAN) {
            return _isEuropeanBarrierBreached(expiry, period, barrierPCT, underlying, strike);
        } else {
            return _isAmericanBarrierBreached(_instrumentId, _barrierId, underlying, strike);
        }
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
            // TODO convert the baseExpo to uint8, and handle both the negative and positive exponent cases
            uint256 price = _toPriceWithUnitDecimals(positiveBasePrice, UNIT, decimals, UNIT_DECIMALS);
            historicalPrices[asset][_timestamp] = HistoricalPrice(false, uint64(block.timestamp), price.safeCastTo128());
            emit HistoricalPriceSet(asset, _timestamp, price, false);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * Updates the breach timestamp of an american barrier 
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _timestamp The timestamp at which the breach occured. The price of the underlyer and strike asset at the provided timestamp should be used to verify.
     */
    function updateAmericanBarrier(uint256 _instrumentId, uint32 _barrierId, uint256 _timestamp) external override onlyOwner {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (_timestamp == 0) {
            // By default we only update barriers on a breach (timestamp 0 to timestamp !0)
            // So this special case means we're overwritting the breach and setting the barrier to be unbreached
            americanBarrierBreaches[_instrumentId][_barrierId] = _timestamp;
            emit AmericanBarrierUpdated(_instrumentId, _barrierId, _timestamp);
            return;
        }
        (uint16 barrierPCT, , uint64 period, uint64 expiry, address underlying, address strike) = _getBarrierInformation(_instrumentId, _barrierId);
        (uint256 price, ) = _getPriceAtTimestamp(underlying, strike, _timestamp);
        (uint256 spotPriceAtCreation,) = _getPriceAtTimestamp(underlying, strike, expiry - period);
        if (spotPriceAtCreation == 0) revert OC_PriceNotReported();
        // TODO is there a better way to do the rounding? This rounding favours one case over another but should cancel out on the whole?
        uint256 barrierBreachPrice = spotPriceAtCreation.mulDivUp(barrierPCT, 100);
        bool americanBarrierBreached = _compareBarrierPrices(barrierBreachPrice, price, barrierPCT);
        if (!americanBarrierBreached) revert IO_AmericanBarrierNotBreached();
        americanBarrierBreaches[_instrumentId][_barrierId] = _timestamp;
        emit AmericanBarrierUpdated(_instrumentId, _barrierId, _timestamp);
    }


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
     * @dev set the pyth contract for this oracle
     * @param _pyth the address of the pyth contract
     */
    function setPyth(address _pyth) external onlyOwner {
        if (_pyth == address(0)) revert OC_ZeroAddress();
        pyth = IPyth(_pyth);
        emit PythUpdated(_pyth);
    }

    /**
     * @dev set the InstrumentGrappa contract for this oracle
     * @param _instrumentGrappa the address of the InstrumentGrappa contract
     */
    function setInstrumentGrappa(address _instrumentGrappa) external override onlyOwner {
        if (_instrumentGrappa == address(0)) revert OC_ZeroAddress();
        instrumentGrappa = IInstrumentGrappa(_instrumentGrappa);
        emit InstrumentGrappaUpdated(_instrumentGrappa);
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

    function _getBarrierInformation(uint256 _instrumentId, uint32 _barrierId) internal view returns (uint16 barrierPCT, BarrierExerciseType exerciseType, uint64 period, uint64 expiry, address underlying, address strike) {
        (uint16 _barrierPCT, , , BarrierExerciseType _exerciseType) = instrumentGrappa.getDetailFromBarrierId(_barrierId);
        (uint64 _period, , , , Option[] memory options) = instrumentGrappa.getDetailFromInstrumentId(_instrumentId);
        (, uint40 productId, uint64 _expiry, , ) = instrumentGrappa.getDetailFromTokenId(options[0].tokenId);
        (, , address _underlying, , address _strike, , ,) = instrumentGrappa.getDetailFromProductId(productId);
        return (_barrierPCT, _exerciseType, _period, _expiry, _underlying, _strike);
    }

    function _isAmericanBarrierBreached(uint256 _instrumentId, uint32 _barrierId, address underlying, address strike) internal view returns (bool isBreached, bool isFinalized) {
        uint256 americanBarrierBreachTimestamp = americanBarrierBreaches[_instrumentId][_barrierId];
        if (americanBarrierBreachTimestamp == 0) {
            return (false, true);
        } else {
            (, bool isAmericanBarrierBreachPriceFinalized) = _getPriceAtTimestamp(underlying, strike, americanBarrierBreachTimestamp);
            return (true, isAmericanBarrierBreachPriceFinalized);
        }
    }

    function _isEuropeanBarrierBreached(uint64 expiry, uint64 period, uint16 barrierPCT, address underlying, address strike) internal view returns (bool isBreached, bool isFinalized) {
        (uint256 spotPriceAtCreation, bool isSpotPriceAtCreationFinalized) = _getPriceAtTimestamp(underlying, strike, expiry - period);
        if (spotPriceAtCreation == 0) revert OC_PriceNotReported();
        (uint256 expiryPrice, bool isExpiryPriceFinalized) = _getPriceAtTimestamp(underlying, strike, expiry);
        if (expiryPrice == 0) revert OC_PriceNotReported();
        bool europeanBarrierFinalized = isSpotPriceAtCreationFinalized && isExpiryPriceFinalized;
        // TODO is there a better way to do the rounding? This rounding favours one case over another but should cancel out on the whole?
        uint256 barrierBreachPrice = spotPriceAtCreation.mulDivUp(barrierPCT, 100);
        bool europeanBarrierBreached = _compareBarrierPrices(barrierBreachPrice, expiryPrice, barrierPCT);
        return (europeanBarrierBreached, europeanBarrierFinalized);
    }

    function _compareBarrierPrices(uint256 _barrierBreachPrice, uint256 _comparisonPrice, uint16 _barrierPCT) internal pure returns (bool isBreached) {
        if (_barrierPCT < 100) {
            return _comparisonPrice < _barrierBreachPrice;
        } else {
            return _comparisonPrice > _barrierBreachPrice;
        }
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
