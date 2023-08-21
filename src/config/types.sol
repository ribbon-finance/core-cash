// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./enums.sol";

/**
 * @dev struct representing an instrument which
 *             is a construction of options and coupons
 * @param period duration of instrument
 * @param engineId representing engine id
 * @param autocallId representing the autocall feature if included
 * @param coupons packed uint of all the coupons (64 bits each) in the instrument (4 max)
 * @param options array of all the options in the instrument
 */
struct Instrument {
    uint64 period;
    uint8 engineId;
    uint40 autocallId;
    uint256 coupons;
    Option[] options;
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
 * @param isCoupon whether it is coupon (true) or option (false)
 * @param index index in coupons or options array
 * @param engineId engine id
 * @param collateralId grappa asset id
 * @param amount amount the asset
 */
struct InstrumentComponentBalance {
    bool isCoupon;
    uint8 index;
    uint8 engineId;
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
