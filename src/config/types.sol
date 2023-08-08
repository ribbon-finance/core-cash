// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./enums.sol";

/**
 * @dev struct representing an instrument which
 *             is a construction of options and coupons
 * @param maturity maturity of the instrument
 * @param options array of all the options in the instrument
 * @param coupons array of all the coupons in the instrument
 * @param autocall struct representing the autocall feature if included
 */
struct Instrument {
    uint40 maturity;
    Option[] options;
    Coupon[] coupons;
    Autocall autocall;
}

/**
 * @dev struct representing an option with a barrier
 * @param baseTokenId id of the base token defined in TokenIdUtil.sol
 * @param leverageFactor leverage factor (ONLY PUTS)
 * @param barrierPCT percentage of the barrier relative to initial spot price
 * @param barrierId id of the barrier
 */
struct Option {
    uint256 baseTokenId;
    uint8 leverageFactor;
    uint16 barrierPCT;
    uint40 barrierId;
}

/**
 * @dev struct representing a coupon
 * @param couponPCT percentage coupon of the notional
 * @param numInstallements number of coupon installments (ONLY AUTOCALL COUPONS)
 * @param couponType struct representing coupon type (!NONE ONLY AUTOCALL COUPONS)
 * @param barrierPCT percentage of the barrier relative to initial spot price
 * @param barrierId id of the barrier
 */
struct Coupon {
    uint8 couponPCT;
    uint8 numInstallements;
    CouponType couponType;
    uint16 barrierPCT;
    uint24 barrierId;
}

/**
 * @dev struct representing an autocall feature
 * @param isReverse whether it is a reverse autocallable
 * @param barrierPCT percentage of the barrier relative to initial spot price
 * @param barrierId id of the barrier
 */
struct Autocall {
    bool isReverse;
    uint16 barrierPCT;
    uint24 barrierId;
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
