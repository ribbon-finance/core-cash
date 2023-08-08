// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./enums.sol";

/**
 * @dev struct representing an instrument which
 *             is a construction of options and coupons
 * @param maturity maturity of the instrument
 * @param options mapping of all the options in the instrument
 * @param coupons mapping of all the coupons in the instrument
 * @param autocall struct representing the autocall feature if included
 */
struct Instrument {
    uint40 maturity;
    mapping(uint256 => Option) options;
    mapping(uint256 => Coupon) coupons;
    Autocall autocall;
}

/**
 * @dev struct representing an option with a barrier
 * @param isLong whether the holder is long/short the option
 * @param baseTokenId id of the base token defined in TokenIdUtil.sol
 * @param leverageFactor leverage factor (ONLY PUTS)
 * @param barrier struct representing barrier feature of the option
 */
struct Option {
    bool isLong;
    uint256 baseTokenId;
    uint8 leverageFactor;
    Barrier barrier;
}

/**
 * @dev struct representing a coupon
 * @param couponPCT percentage coupon of the notional
 * @param numInstallements number of coupon installments (ONLY AUTOCALL COUPONS)
 * @param barrier struct representing barrier feature of the coupon
 * @param couponType struct representing coupon type (!NONE ONLY AUTOCALL COUPONS)
 */
struct Coupon {
    uint8 couponPCT;
    uint8 numInstallements;
    Barrier barrier;
    CouponType couponType;
}

/**
 * @dev struct representing an autocall feature
 * @param isReverse whether it is a reverse autocallable
 * @param barrier struct representing barrier feature of the autocall
 */
struct Autocall {
    bool isReverse;
    Barrier barrier;
}

/**
 * @dev struct representing a barrier feature of an option, coupon, or autocall feature
 * @param barrierPCT percentage of the barrier relative to initial spot price
 * @param isValid barrier validity (ONLY AMERICAN EXERCISE TYPE)
 * @param observationFrequency frequency of observations (ex: 1d, 1wk, 1mo) represented in seconds
 * @param barrierType type of the barrier
 * @param exerciseType exercise type
 */
struct Barrier {
    uint16 barrierPCT;
    bool isValid;
    uint40 observationFrequency;
    BarrierType barrierType;
    ExerciseType exerciseType;
}

/**
 * @dev struct representing the current balance for a given collateral
 * @param collateralId grappa asset id
 * @param amount amount the asset
 */
struct Balance {
    uint8 collateralId;
    uint80 amount;
}

/**
 * @dev struct containing assets detail for an product
 * @param underlying    underlying address
 * @param strike        strike address
 * @param collateral    collateral address
 * @param collateralDecimals collateral asset decimals
 */
struct ProductDetails {
    address oracle;
    uint8 oracleId;
    address engine;
    uint8 engineId;
    address underlying;
    uint8 underlyingId;
    uint8 underlyingDecimals;
    address strike;
    uint8 strikeId;
    uint8 strikeDecimals;
    address collateral;
    uint8 collateralId;
    uint8 collateralDecimals;
}

// todo: update doc
struct ActionArgs {
    ActionType action;
    bytes data;
}

struct BatchExecute {
    address subAccount;
    ActionArgs[] actions;
}

/**
 * @dev asset detail stored per asset id
 * @param addr address of the asset
 * @param decimals token decimals
 */
struct AssetDetail {
    address addr;
    uint8 decimals;
}
