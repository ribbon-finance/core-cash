// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

///@dev unit used for option amount and strike prices
uint8 constant UNIT_DECIMALS = 6;

///@dev unit used for percentages
uint8 constant UNIT_PERCENTAGE_DECIMALS = 2;

///@dev unit scaled used to convert amounts.
uint256 constant UNIT = 10 ** 6;

///@dev unit percentage representing 100% to 2 decimals (e.g. 10% = 10 * 10**2 = 1000)
uint16 constant UNIT_PERCENTAGE = 10000;

///@dev int scaled used to convert amounts.
int256 constant sUNIT = int256(10 ** 6);

///@dev basis point for 100%.
uint256 constant BPS = 10000;

///@dev maximum dispute period for oracle
uint256 constant MAX_DISPUTE_PERIOD = 365 days;

///@dev maximum amount of options in an instrument
uint8 constant MAX_OPTION_CONSTRUCTION = 4;

///@dev maximum amount of coupons in an instrument
uint8 constant MAX_COUPON_CONSTRUCTION = 4;

///@dev hundred pct (100% with two decimals)
uint16 constant HUNDRED_PCT = 10000;
