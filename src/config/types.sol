// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./enums.sol";

/**
 * @dev struct representing an instrument which
 *             is a construction of options and coupons
 * @param oracleId representing oracle id
 * @param engineId representing engine id
 * @param autocallId representing the autocall feature if included
 * @param period duration of instrument
 * @param coupons packed uint of all the coupons (64 bits each) in the instrument (4 max)
 * @param options array of all the options in the instrument
 */
struct Instrument {
    uint8 oracleId;
    uint8 engineId;
    uint32 autocallId;
    uint64 period;
    uint256 coupons;
    Option[] options;
}

struct InstrumentExtended {
    uint8 oracleId;
    uint8 engineId;
    uint64 period;
    Barrier autocall;
    Coupon[] coupons;
    OptionExtended[] options;
}

struct Coupon {
    uint16 couponPCT;
    bool isPartitioned;
    CouponType couponType;
    Barrier barrier;
}

/**
 * @dev struct representing an option and allocation
 * @param participationPCT participation pct
 * @param barrierId barrier id
 * @param tokenId token id
 */
struct Option {
    uint16 participationPCT;
    uint32 barrierId;
    uint256 tokenId;
}

struct OptionExtended {
    uint16 participationPCT;
    Barrier barrier;
    uint256 tokenId;
}

struct Barrier {
    uint16 barrierPCT;
    BarrierObservationFrequencyType observationFrequency;
    BarrierTriggerType triggerType;
}

/// @dev internal struct to bypass stack too deep issues
struct BreachDetail {
    uint16 barrierPCT;
    uint256 breachThreshold;
    BarrierExerciseType exerciseType;
    uint64 period;
    uint64 expiry;
    address oracle;
    address underlying;
    address strike;
    uint256 frequency;
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
 * @dev struct representing the balance for a given instrument component
 * @param index index in coupons or options array
 * @param isCoupon whether it is coupon (true) or option (false)
 * @param tokenId token id
 * @param amount amount the asset
 */
struct InstrumentComponentBalance {
    uint8 index;
    bool isCoupon;
    uint256 tokenId;
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
