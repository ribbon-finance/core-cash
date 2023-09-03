// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OracleHelper} from "./OracleHelper.sol";

import {PythInstrumentOracleDisputable} from "../../../src/core/oracles/PythInstrumentOracleDisputable.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import "pyth-sdk-solidity/MockPyth.sol";

import "../../../src/config/enums.sol";
import "../../../src/config/types.sol";
import "../../../src/config/constants.sol";
import "../../../src/core/oracles/errors.sol";

contract PythInstrumentOracleDisputableTest is OracleHelper {
    PythInstrumentOracleDisputable private oracle;
    uint64 public immutable initialTimestamp = 100;

    function setUp() public {
        oracle = new PythInstrumentOracleDisputable(address(this), PYTH, COMBINED_PRICE_FEEDS, COMBINED_ADDRESSES);
        vm.warp(initialTimestamp);
    }

    // #reportPrice

    function testReportPriceWithoutOwnerReverts() public {
        (uint256[] memory tripleInstrumentIds, uint32[] memory tripleBarrierIds) = getInstrumentAndBarrierIds(3);
        address[] memory underlyers = new address[](3);
        underlyers[0] = WETH;
        underlyers[1] = USDC;
        underlyers[2] = WBTC;
        bytes[] memory dummyPythUpdateData = new bytes[](3);
        // We use 3 to represent USDC, WETH and WBTC
        for (uint8 i = 0; i < 3; i++) {
            dummyPythUpdateData[i] = bytes("0");
        }
        vm.startPrank(NON_OWNER);
        vm.deal(NON_OWNER, 1 ether);
        // This is as if we want to update the price for USDC, WETH and WBTC but only pass WETH as the underlyer
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.reportPrice{value: 1 wei}(
            dummyPythUpdateData,
            COMBINED_PRICE_FEEDS,
            uint64(block.timestamp) - 1,
            tripleInstrumentIds,
            tripleBarrierIds,
            underlyers
        );
        vm.stopPrank();
    }

    function testReportPriceWithDifferentUnderlyerLengthReverts() public {
        (uint256[] memory tripleInstrumentIds, uint32[] memory tripleBarrierIds) = getInstrumentAndBarrierIds(3);
        address[] memory underlyers = new address[](1);
        underlyers[0] = WETH;
        bytes[] memory dummyPythUpdateData = new bytes[](3);
        // We use 3 to represent USDC, WETH and WBTC
        for (uint8 i = 0; i < 3; i++) {
            dummyPythUpdateData[i] = bytes("0");
        }
        vm.expectRevert(OC_ArgumentsLengthError.selector);
        // This is as if we want to update the price for USDC, WETH and WBTC but only pass WETH as the underlyer
        oracle.reportPrice{value: 1 wei}(
            dummyPythUpdateData,
            COMBINED_PRICE_FEEDS,
            uint64(block.timestamp) - 1,
            tripleInstrumentIds,
            tripleBarrierIds,
            underlyers
        );
    }

    // #updateBarrier

    function testUpdateBarrierWithoutOwnerReverts() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 seconds ago
        oracle.setPriceBackup(WETH, block.timestamp - 1, 1);
        vm.startPrank(NON_OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        vm.stopPrank();
    }

    function testUpdateBarrierSingleFirstUpdate() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 seconds ago
        setPriceBackupWithChecks(WETH, block.timestamp - 1, 1, oracle);
        // This makes the last barrier update 1 second ago
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(singleInstrumentIds[0], singleBarrierIds[0], 0), block.timestamp - 1);
    }

    function testUpdateBarrierSingleSubsequentUpdate() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        setPriceBackupWithChecks(WETH, block.timestamp - 1, 1, oracle);
        setPriceBackupWithChecks(WETH, block.timestamp - 2, 2, oracle);
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
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 seconds ago
        setPriceBackupWithChecks(WETH, block.timestamp - 1, 1, oracle);
        oracle.updateBarrier(doubleInstrumentIds, doubleBarrierIds, block.timestamp - 1, underlyers);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[0], doubleBarrierIds[0], 0), block.timestamp - 1);
        assertEq(oracle.barrierUpdates(doubleInstrumentIds[1], doubleBarrierIds[1], 0), block.timestamp - 1);
    }

    function testUpdateBarrierMultipleSubsequentUpdate() public {
        (uint256[] memory doubleInstrumentIds, uint32[] memory doubleBarrierIds) = getInstrumentAndBarrierIds(2);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        setPriceBackupWithChecks(WETH, block.timestamp - 1, 1, oracle);
        setPriceBackupWithChecks(WETH, block.timestamp - 2, 2, oracle);
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
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        setPriceBackupWithChecks(WETH, block.timestamp - 1, 1, oracle);
        setPriceBackupWithChecks(WETH, block.timestamp - 2, 2, oracle);
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
        underlyers[0] = (WETH);
        vm.expectRevert(OC_CannotReportForFuture.selector);
        oracle.updateBarrier(emptyInstrumentIds, emptyBarrierIds, block.timestamp + 1, underlyers);
    }

    function testUpdateBarrierZeroTimestampReverts() public {
        (uint256[] memory emptyInstrumentIds, uint32[] memory emptyBarrierIds) = getInstrumentAndBarrierIds(0);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        vm.expectRevert(IO_InvalidTimestamp.selector);
        oracle.updateBarrier(emptyInstrumentIds, emptyBarrierIds, 0, underlyers);
    }

    function testUpdateBarrierEmptyInstrumentAndBarrierIdReverts() public {
        (uint256[] memory emptyInstrumentIds, uint32[] memory emptyBarrierIds) = getInstrumentAndBarrierIds(0);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        vm.expectRevert(OC_ArgumentsLengthError.selector);
        oracle.updateBarrier(emptyInstrumentIds, emptyBarrierIds, block.timestamp - 1, underlyers);
    }

    function testUpdateBarrierDifferentInstrumentAndBarrierIdLengthReverts() public {
        (uint256[] memory singleInstrumentIds,) = getInstrumentAndBarrierIds(1);
        (, uint32[] memory doubleBarrierIds) = getInstrumentAndBarrierIds(2);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
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
        underlyers[0] = (WETH);
        vm.expectRevert(OC_PriceNotReported.selector);
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
    }

    function testUpdateBarrierTimestampBeforeLastUpdateReverts() public {
        (uint256[] memory singleInstrumentIds, uint32[] memory singleBarrierIds) = getInstrumentAndBarrierIds(1);
        address[] memory underlyers = new address[](1);
        underlyers[0] = (WETH);
        // We use the setPriceBackup to set a price for this timestamp 1 and 2 seconds ago
        setPriceBackupWithChecks(WETH, block.timestamp - 1, 1, oracle);
        setPriceBackupWithChecks(WETH, block.timestamp - 2, 2, oracle);
        // This makes the last barrier update 1 second ago
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 1, underlyers);
        vm.expectRevert(IO_InvalidTimestamp.selector);
        // We now try to update the barrier for 2 seconds ago which should revert
        oracle.updateBarrier(singleInstrumentIds, singleBarrierIds, block.timestamp - 2, underlyers);
    }
}
