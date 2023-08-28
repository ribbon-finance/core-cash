// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// interfaces
import {IOracle} from "../../interfaces/IOracle.sol";
// abstract
import {BaseOracle} from "./abstract/BaseOracle.sol";

// constants and types
import "./errors.sol";
import "../../config/constants.sol";

/**
 * @title PythOracle
 * @dev return base / quote price, with 6 decimals
 */
contract PythOracle is IOracle, BaseOracle {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /// @notice 0x4305FB66699C3B2702D4d05CF36551390A4c69C6. https://docs.pyth.network/documentation/pythnet-price-feeds/evm.
    IPyth public immutable pyth;

    // pyth price feed IDs (https://pyth.network/developers/price-feed-ids) => asset
    mapping(bytes32 => address) public priceFeedIds;

    /*///////////////////////////////////////////////////////////////
                                 Events
    //////////////////////////////////////////////////////////////*/

    event PriceFeedIDUpdated(bytes32 id, address base);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth) BaseOracle(_owner) {
        if (_pyth == address(0)) revert OC_ZeroAddress();
        pyth = IPyth(_pyth);
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
    function maxDisputePeriod() external view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @notice report pyth price at a timestamp and write to storage
     * @notice Since pyth price feeds are USD denominated, stored prices are always coverted to {UNIT_DECIMALS} decimals
     * @dev anyone can call this function and set the price for a given timestamp
     */
    function reportPrice(bytes[] calldata _pythUpdateData, bytes32[] calldata priceIds, address _quote, uint64 _timestamp)
        external
        payable
    {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        uint256 updateFee = pyth.getUpdateFee(_pythUpdateData);
        PythStructs.PriceFeed[] memory priceFeeds =
            pyth.parsePriceFeedUpdates{value: updateFee}(_pythUpdateData, priceIds, _timestamp, _timestamp);
        for (uint256 i = 0; i < priceFeeds.length; i++) {
            bytes32 id = priceFeeds[i].id;
            address base = priceFeedIds[id];
            if (base == address(0)) revert PY_AssetPriceFeedNotSet();
            uint256 publishTime = priceFeeds[i].price.publishTime;
            if (publishTime != _timestamp) revert PY_DifferentPublishProvidedTimestamps();
            if (historicalPrices[base][_quote][_timestamp].reportAt != 0) revert OC_PriceReported();
            uint256 price = _toPriceWithUnitDecimals(priceFeeds[i].price);
            historicalPrices[base][_quote][_timestamp] = HistoricalPrice(false, uint64(block.timestamp), price.safeCastTo128());
            emit HistoricalPriceSet(base, _quote, _timestamp, price, false);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev set the pyth price feed ID for an asset
     * @param _base base asset. for ETH/USDC price, ETH is the base asset
     * @param _id the bytes 32 ID of the price feed
     */
    function setPriceFeedID(address _base, bytes32 _id) external onlyOwner {
        if (_id == bytes32(0)) revert PY_InvalidPriceFeedID();
        if (_base == address(0)) revert OC_ZeroAddress();

        priceFeedIds[_id] = _base;

        emit PriceFeedIDUpdated(_id, _base);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Reference taken from pyth's example https://github.com/pyth-network/pyth-crosschain/blob/71ce45698b4580b97e90d1d20cad8c4493e2b799/target_chains/ethereum/examples/oracle_swap/contract/src/OracleSwap.sol#L93
     * @param price pyth price struct to be converted
     */
    function _toPriceWithUnitDecimals(PythStructs.Price memory _price) private pure returns (uint256 price) {
        if (_price.price < 0 || _price.expo > 0 || _price.expo < -255) {
            revert PY_PythPriceConversionError();
        }

        uint8 priceDecimals = uint8(uint32(-1 * _price.expo));

        if (UNIT_DECIMALS - priceDecimals >= 0) {
            return uint256(uint64(_price.price)) * 10 ** uint32(UNIT_DECIMALS - priceDecimals);
        } else {
            return uint256(uint64(_price.price)) / 10 ** uint32(priceDecimals - UNIT_DECIMALS);
        }
    }
}
