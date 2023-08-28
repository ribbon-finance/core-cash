// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// constants and types
import "../errors.sol";
import "../../../config/constants.sol";

/**
 * @title BaseOracle
 * @author @antoncoding
 * @dev return base / quote price, with 6 decimals
 */
abstract contract BaseOracle is Ownable {
    using FixedPointMathLib for uint256;

    struct HistoricalPrice {
        bool isDisputed;
        uint64 reportAt;
        uint128 price;
    }

    ///@dev base => quote => timestamp => price.
    mapping(address => mapping(address => mapping(uint256 => HistoricalPrice))) public historicalPrices;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event HistoricalPriceSet(address base, address quote, uint256 timestamp, uint256 price, bool isDispute);

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
    function isPriceFinalized(address _base, address _quote, uint256 _timestamp) external view returns (bool) {
        return _isPriceFinalized(_base, _quote, _timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev this oracle has no dispute mechanism, so always return true.
     *      a un-reported price should have reverted at this point.
     */
    function _isPriceFinalized(address, address, uint256) internal view virtual returns (bool) {
        return true;
    }

    /**
     * @dev get price of underlying at a particular timestamp, denominated in strike asset.
     *         can revert if timestamp is in the future, or the price has not been reported by authorized party
     * @param _base base asset. for ETH/USD price, ETH is the base asset
     * @param _quote quote asset. for ETH/USD price, USD is the quote asset
     * @param _timestamp timestamp to check
     * @return price with 6 decimals
     */
    function _getPriceAtTimestamp(address _base, address _quote, uint256 _timestamp)
        internal
        view
        returns (uint256 price, bool isFinalized)
    {
        HistoricalPrice memory data = historicalPrices[_base][_quote][_timestamp];
        if (data.reportAt == 0) revert OC_PriceNotReported();

        return (data.price, _isPriceFinalized(_base, _quote, _timestamp));
    }

    /**
     * @notice  convert prices from aggregator of base & quote asset to base / quote, denominated in UNIT
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
