// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import test base and helpers.
import "forge-std/Test.sol";
import {OracleHelper} from "./OracleHelper.sol";

import {PythInstrumentOracleDisputable} from "../../../src/core/oracles/PythInstrumentOracleDisputable.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import "pyth-sdk-solidity/MockPyth.sol";

import "../../../src/config/enums.sol";
import "../../../src/config/types.sol";
import "../../../src/config/constants.sol";
import "../../../src/core/oracles/errors.sol";

contract PythInstrumentOracleDisputableTest is OracleHelper, Test {
    PythInstrumentOracleDisputable private oracle;
    uint64 public immutable initialTimestamp = 100;

    function setUp() public {
        oracle = new PythInstrumentOracleDisputable(address(this), PYTH, COMBINED_PRICE_FEEDS, COMBINED_ADDRESSES);
        vm.warp(initialTimestamp);
    }

    // reportPrice() tests

    // function testReportPriceReverts() public {
    //     oracle.reportPrice([bytes("DummyUpdaateOne")], COMBINED_PRICE_FEEDS, block.timestamp, [], [], []);
    //     vm.expectRevert(OC_ArgumentsLengthError());
    //     bytes[] calldata _pythUpdateData,
    //     bytes32[] calldata _priceIds,
    //     uint64 _timestamp,
    //     uint256[] calldata _instrumentIds,
    //     uint32[] calldata _barrierIds,
    //     address[] calldata _barrierUnderlyerAddresses
    // }

    // updateBarrier() tests

    function testUpdateBarrierSingleFirstUpdate() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        // We use the setPriceBackup to set a price for this timestamp 1 seconds ago
        oracle.setPriceBackup(USDC, block.timestamp - 1, 1);
        // This makes the last barrier update 1 second ago
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(singleInstrumentIds[0], singleBarrierIds[0], 0), block.timestamp - 1);
    }

    function testUpdateBarrierSingleSubsequentUpdate() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        oracle.setPriceBackup(USDC, block.timestamp - 1, 1);
        oracle.setPriceBackup(USDC, block.timestamp - 2, 1);
        // This makes the last barrier update 2 seconds ago
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 2, underlyers);
        assertEq(oracle.barrierUpdates(singleInstrumentIds[0], singleBarrierIds[0], 0), block.timestamp - 2);
        // We do another update for 1 second ago
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(singleInstrumentIds[0], singleBarrierIds[0], 1), block.timestamp - 1);
    }

    function testUpdateBarrierMultipleFirstUpdate() public {
        (uint256[] memory doubleInstrumentIds, uint32[] memory doubleBarrierIds) = getInstrumentAndBarrierIds(2);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        // We use the setPriceBackup to set a price for this timestamp 1 seconds ago
        oracle.setPriceBackup(USDC, block.timestamp - 1, 1);
        oracle.updateBarrier(doubleInstrumentIds, doubleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[0], doubleBarrierIds[0], 0), block.timestamp - 1);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[1], doubleBarrierIds[1], 0), block.timestamp - 1);
    }

    function testUpdateBarrierMultipleSubsequentUpdate() public {
        (uint256[] memory doubleInstrumentIds, uint32[] memory doubleBarrierIds) = getInstrumentAndBarrierIds(2);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        oracle.setPriceBackup(USDC, block.timestamp - 1, 1);
        oracle.setPriceBackup(USDC, block.timestamp - 2, 1);
        // This makes the last barrier update 2 seconds ago
        oracle.updateBarrier(doubleInstrumentIds, doubleBarrierIds, block.timestamp - 2, underlyers);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[0], doubleBarrierIds[0], 0), block.timestamp - 2);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[1], doubleBarrierIds[1], 0), block.timestamp - 2);
        // We do another update for 1 second ago
        oracle.updateBarrier(doubleInstrumentIds, doubleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[0], doubleBarrierIds[0], 1), block.timestamp - 1);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[1], doubleBarrierIds[1], 1), block.timestamp - 1);
    }

    function testUpdateBarrierMultipleMixedUpdate() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        (uint256[] memory doubleInstrumentIds, uint32[] memory doubleBarrierIds) = getInstrumentAndBarrierIds(2);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        oracle.setPriceBackup(USDC, block.timestamp - 1, 1);
        oracle.setPriceBackup(USDC, block.timestamp - 2, 1);
        // This makes the last barrier update 2 seconds ago
        oracle.updateBarrier(doubleInstrumentIds, doubleBarrierIds, block.timestamp - 2, underlyers);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[0], doubleBarrierIds[0], 0), block.timestamp - 2);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[1], doubleBarrierIds[1], 0), block.timestamp - 2);
        // We do another update for 1 second ago, but only for the first instrument-barrier pair
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(singleInstrumentIds[0], singleBarrierIds[0], 1), block.timestamp - 1);
    }

    function testUpdateBarrierTimestampForFutureReverts() public {
        (uint256[] memory emptyInstrumentIds, uint32[] memory emptyBarrierIds) = getInstrumentAndBarrierIds(0);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        vm.expectRevert(OC_CannotReportForFuture.selector);
        oracle.updateBarrier(emptyInstrumentIds, emptyBarrierIds, block.timestamp + 1, underlyers);
    }

    function testUpdateBarrierZeroTimestampReverts() public {
        (uint256[] memory emptyInstrumentIds, uint32[] memory emptyBarrierIds) = getInstrumentAndBarrierIds(0);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        vm.expectRevert(IO_InvalidTimestamp.selector);
        oracle.updateBarrier(emptyInstrumentIds, emptyBarrierIds, 0, underlyers);
    }

    function testUpdateBarrierEmptyInstrumentAndBarrierIdReverts() public {
        (uint256[] memory emptyInstrumentIds, uint32[] memory emptyBarrierIds) = getInstrumentAndBarrierIds(0);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        vm.expectRevert(OC_ArgumentsLengthError.selector);
        oracle.updateBarrier(emptyInstrumentIds, emptyBarrierIds, block.timestamp - 1, underlyers);
    }

    function testUpdateBarrierDifferentInstrumentAndBarrierIdLengthReverts() public {
        (uint256[] memory singleInstrumentIds,) = getInstrumentAndBarrierIds(1);
        (, uint32[] memory doubleBarrierIds) = getInstrumentAndBarrierIds(2);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        vm.expectRevert(OC_ArgumentsLengthError.selector);
        oracle.updateBarrier(singleInstrumentIds, doubleBarrierIds, block.timestamp - 1, underlyers);
    }

    function testUpdateBarrierEmptyUnderlyerReverts() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](0);
        vm.expectRevert(OC_ArgumentsLengthError.selector);
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
    }

    function testUpdateBarrierAssetPriceNotReportedReverts() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        vm.expectRevert(OC_PriceNotReported.selector);
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
    }

    function testUpdateBarrierTimestampBeforeLastUpdateReverts() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (USDC);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        oracle.setPriceBackup(USDC, block.timestamp - 1, 1);
        oracle.setPriceBackup(USDC, block.timestamp - 2, 1);
        // This makes the last barrier update 1 second ago
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        vm.expectRevert(IO_InvalidTimestamp.selector);
        // We now try to update the barrier for 2 seconds ago which should revert
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 2, underlyers);
    }
}
