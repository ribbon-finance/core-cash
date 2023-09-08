// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// constants and types
import "../errors.sol";
import "../../../config/constants.sol";

/**
 * @title BaseOracle
 * @author @antoncoding
 * @notice stores and returns prices in USD with {UNIT_DECIMALS} decimals. Oracles that implement this should be USD-denominated (e.g. ETH/USD is fine while ETH/BTC is not)
 */
abstract contract BaseOracle is Ownable {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    uint256 public gracePeriod;

    struct HistoricalPrice {
        bool isDisputed;
        uint64 reportAt;
        uint128 price;
    }

    ///@notice stable assets will always return UNIT. if you want to use the actual price (e.g. if USDC depegs), set its mapping to false.
    mapping(address => bool) public stableAssets;

    ///@dev base => timestamp => price.
    mapping(address => mapping(uint256 => HistoricalPrice)) public historicalPrices;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event HistoricalPriceSet(address base, uint256 timestamp, uint256 price, bool isDispute);

    event StableAssetUpdated(address asset, bool isStable);

    event GracePeriodUpdated(uint256 gracePeriod);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        // solhint-disable-next-line reason-string
        if (_owner == address(0)) revert OC_ZeroAddress();

        _transferOwnership(_owner);
    }

    /*///////////////////////////////////////////////////////////////
                            External functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev view function to check if dispute period is over
     */
    function isPriceFinalized(address _base, uint256 _timestamp) external view returns (bool) {
        return _isPriceFinalized(_base, _timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                            Admin functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev owner can set a price if the the price has not been pushed after the grace period
     * @param _base base asset
     * @param _timestamp timestamp
     * @param _price price to set
     */
    function setPriceBackup(address _base, uint256 _timestamp, uint256 _price) external onlyOwner {
        HistoricalPrice memory entry = historicalPrices[_base][_timestamp];
        if (entry.reportAt != 0) revert OC_PriceReported();

        if (_timestamp + gracePeriod > block.timestamp) revert OC_GracePeriodNotOver();

        historicalPrices[_base][_timestamp] = HistoricalPrice(true, uint64(block.timestamp), _price.safeCastTo128());

        emit HistoricalPriceSet(_base, _timestamp, _price, true);
    }

    /**
     * @dev sets a stable asset for this oracle
     * @param _asset the address of the asset
     * @param _isStableAsset boolean of if the asset is a stable asset
     */
    function setStableAsset(address _asset, bool _isStableAsset) external onlyOwner {
        if (_asset == address(0)) revert OC_ZeroAddress();
        stableAssets[_asset] = _isStableAsset;
        emit StableAssetUpdated(_asset, _isStableAsset);
    }

    /**
     * @notice sets the grace period after which the owner can write any price for a timestamp through setPriceBackup
     * @param _gracePeriod new grace period in seconds
     */
    function setGracePeriod(uint256 _gracePeriod) external onlyOwner {
        if (_gracePeriod == 0) revert OC_InvalidPeriod();
        gracePeriod = _gracePeriod;
        emit GracePeriodUpdated(_gracePeriod);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev this oracle has no dispute mechanism, so always return true.
     *      a un-reported price should have reverted at this point.
     */
    function _isPriceFinalized(address, uint256) internal view virtual returns (bool) {
        return true;
    }

    /**
     * @dev get price of underlying at a particular timestamp, denominated in strike asset.
     *         can revert if timestamp is in the future, or the price has not been reported by authorized party
     * @param _base base asset. for ETH/USD price, ETH is the base asset
     * @param _timestamp timestamp to check
     * @return price with {UNIT_DECIMALS} decimals
     */
    function _getPriceAtTimestamp(address _base, uint256 _timestamp) internal view returns (uint256 price, bool isFinalized) {
        if (stableAssets[_base]) {
            return (UNIT, true);
        }
        HistoricalPrice memory data = historicalPrices[_base][_timestamp];
        if (data.reportAt == 0) revert OC_PriceNotReported();

        return (data.price, _isPriceFinalized(_base, _timestamp));
    }

    /**
     * @notice  convert prices from aggregator of base & quote asset to base / quote, denominated in UNIT
     * @param _basePrice price of base asset from aggregator
     * @param _baseDecimals decimals of _basePrice
     * @return price base price with {UNIT_DECIMALS} decimals
     */
    function _toPriceWithUnitDecimals(uint256 _basePrice, uint8 _baseDecimals) internal pure returns (uint256) {
        uint256 price;

        if (_baseDecimals == UNIT_DECIMALS) {
            price = _basePrice;
        } else if (_baseDecimals > UNIT_DECIMALS) {
            // Losing precision, just keep first {UNIT_DECIMALS} and drop remainder
            uint8 diff = _baseDecimals - UNIT_DECIMALS;
            price = _basePrice / (10 ** diff);
        } else if (_baseDecimals < UNIT_DECIMALS) {
            // Adding precision, just pad with zeroes
            uint8 diff = UNIT_DECIMALS - _baseDecimals;
            price = _basePrice * (10 ** diff);
        }

        return price;
    }
}
