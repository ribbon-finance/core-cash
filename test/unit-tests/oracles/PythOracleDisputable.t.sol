// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import test base and helpers.
import "forge-std/Test.sol";
import {OracleHelper} from "./OracleHelper.sol";

import {PythOracleDisputable} from "../../../src/core/oracles/PythOracleDisputable.sol";

import "../../../src/config/constants.sol";
import "../../../src/core/oracles/errors.sol";

contract PythOracleDisputableTest is OracleHelper {
    PythOracleDisputable private oracle;
    uint64 public immutable initialTimestamp = 100;
    uint64 private constant expiryToTest = 50;
    uint256 private constant disputedPrice = 3000 * UNIT;

    function setUp() public {
        oracle = new PythOracleDisputable(address(this), PYTH, COMBINED_PRICE_FEEDS, COMBINED_ADDRESSES);
        vm.warp(initialTimestamp);
    }

    // #maxDisputePeriod

    function testMaxDisputePeriod() public {
        assertEq(oracle.maxDisputePeriod(), MAX_DISPUTE_PERIOD);
    }

    // #disputePrice

    function testDisputePrice() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        setPriceBackupWithChecks(WETH, expiryToTest, disputedPrice - 1, oracle);

        oracle.disputePrice(WETH, expiryToTest, disputedPrice);
        (uint256 price, bool isFinalized) = oracle.getPriceAtTimestamp(WETH, USDC, expiryToTest);

        assertEq(price, disputedPrice);
        assertEq(isFinalized, true);
    }

    function testDisputePriceMultipleTimes() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        setPriceBackupWithChecks(WETH, expiryToTest, disputedPrice - 1, oracle);

        oracle.disputePrice(WETH, expiryToTest, disputedPrice);
        (uint256 price, bool isFinalized) = oracle.getPriceAtTimestamp(WETH, USDC, expiryToTest);

        assertEq(price, disputedPrice);
        assertEq(isFinalized, true);

        oracle.disputePrice(WETH, expiryToTest, disputedPrice + 1);
        (uint256 priceNew, bool isFinalizedNew) = oracle.getPriceAtTimestamp(WETH, USDC, expiryToTest);

        assertEq(priceNew, disputedPrice + 1);
        assertEq(isFinalizedNew, true);
    }

    function testDisputePriceWithoutOwnerReverts() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        setPriceBackupWithChecks(WETH, expiryToTest, disputedPrice - 1, oracle);

        vm.prank(NON_OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.disputePrice(WETH, expiryToTest, disputedPrice);
    }

    function testDisputePriceForAssetWithoutDisputePeriodSetReverts() public {
        vm.expectRevert(OC_DisputePeriodNotSet.selector);
        oracle.disputePrice(WETH, expiryToTest, disputedPrice);
    }

    function testDisputePriceForUnreportedPriceReverts() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        vm.expectRevert(OC_PriceNotReported.selector);
        oracle.disputePrice(WETH, expiryToTest, disputedPrice);
    }

    function testDisputePriceAfterDisputePeriodReverts() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        setPriceBackupWithChecks(WETH, expiryToTest, disputedPrice - 1, oracle);

        vm.warp(block.timestamp + MAX_DISPUTE_PERIOD);

        vm.expectRevert(OC_DisputePeriodOver.selector);
        oracle.disputePrice(WETH, expiryToTest, disputedPrice);

        assertEq(oracle.isPriceFinalized(WETH, expiryToTest), true);
    }

    // #setDisputePeriod

    function testSetDisputePeriodWithOwner() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
    }

    function testSetDisputePeriodWithNonOwnerReverts() public {
        vm.prank(NON_OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setDisputePeriod(WETH, MAX_DISPUTE_PERIOD - 1);
    }

    function testSetDisputePeriodThatIsTooHighReverts() public {
        vm.expectRevert(OC_InvalidPeriod.selector);
        oracle.setDisputePeriod(WETH, MAX_DISPUTE_PERIOD + 1);
    }

    // #isPriceFinalized

    function testIsFinalizedIsFalseForUnreportedExpiry() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        assertEq(oracle.isPriceFinalized(WETH, expiryToTest), false);
    }

    function testIsFinalizedIsTrueForStableAsset() public {
        setDisputePeriodWithChecks(USDC, MAX_DISPUTE_PERIOD - 1, oracle);
        setStableAssetWithChecks(USDC, true, oracle);
        assertEq(oracle.isPriceFinalized(USDC, expiryToTest), true);
    }

    function testIsFinalizedIsFalseForNonStableAssetIfDisputePeriodNotOver() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        defaultReportPrice(disputedPrice, expiryToTest, oracle);
        vm.warp(block.timestamp + (oracle.disputePeriod(WETH) - 1));
        assertEq(oracle.isPriceFinalized(WETH, expiryToTest), false);

    }

    function testIsFinalizedIsTrueForNonStableAssetIfDisputePeriodOver() public {
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        defaultReportPrice(disputedPrice, expiryToTest, oracle);
        vm.warp(block.timestamp + (oracle.disputePeriod(WETH) + 1));
        assertEq(oracle.isPriceFinalized(WETH, expiryToTest), true);
    }

    function testIsFinalizedForStableAssetWithoutDisputePeriodReverts() public {
        setStableAssetWithChecks(USDC, true, oracle);
        vm.expectRevert(OC_DisputePeriodNotSet.selector);
        oracle.isPriceFinalized(WETH, expiryToTest);
    }

    function testIsFinalizedForNonStableAssetWithoutDisputePeriodReverts() public {
        setPriceBackupWithChecks(WETH, expiryToTest, disputedPrice - 1, oracle);
        vm.warp(block.timestamp + MAX_DISPUTE_PERIOD);
        vm.expectRevert(OC_DisputePeriodNotSet.selector);
        oracle.isPriceFinalized(WETH, expiryToTest);
        setDisputePeriodWithChecks(WETH, MAX_DISPUTE_PERIOD - 1, oracle);
        assertEq(oracle.isPriceFinalized(WETH, expiryToTest), true);
    }
}
