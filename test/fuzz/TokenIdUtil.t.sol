// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {TokenIdUtil} from "../../src/libraries/TokenIdUtil.sol";

import "../../src/config/enums.sol";

contract TokenIdUtilTest is Test {
    function testTokenIdHigherThan0(uint8 tokenType, uint40 productId, uint64 expiry, uint64 longStrike, uint64 shortStrike)
        public
    {
        vm.assume(tokenType < 4);
        vm.assume(productId > 0);

        uint256 id = TokenIdUtil.getTokenId(TokenType(tokenType), productId, expiry, longStrike, shortStrike);

        assertGt(id, 0);
    }

    function testBarrierIdHigherThan0(
        uint16 barrierPCT,
        BarrierObservationFrequencyType observationFrequency,
        BarrierTriggerType triggerType,
        BarrierExerciseType exerciseType
    ) public {
        vm.assume(observationFrequency <= type(BarrierObservationFrequencyType).max);
        vm.assume(triggerType <= type(BarrierTriggerType).max);
        vm.assume(exerciseType <= type(BarrierExerciseType).max);

        uint256 id = TokenIdUtil.getBarrierId(barrierPCT, observationFrequency, triggerType, exerciseType);

        assertGt(id, 0);
    }

    function testTokenIdFormatAndParseAreMirrored(
        uint8 tokenType,
        uint40 productId,
        uint64 expiry,
        uint64 longStrike,
        uint64 shortStrike
    ) public {
        vm.assume(tokenType < 4);
        vm.assume(productId > 0);

        uint256 id = TokenIdUtil.getTokenId(TokenType(tokenType), productId, expiry, longStrike, shortStrike);
        (TokenType _tokenType, uint40 _productId, uint64 _expiry, uint64 _longStrike, uint64 _shortStrike) =
            TokenIdUtil.parseTokenId(id);

        assertEq(uint8(tokenType), uint8(_tokenType));
        assertEq(productId, _productId);
        assertEq(expiry, _expiry);
        assertEq(longStrike, _longStrike);
        assertEq(shortStrike, _shortStrike);
    }

    function testTokenIdGetAndParseAreMirrored(
        uint8 tokenType,
        uint40 productId,
        uint256 expiry,
        uint256 longStrike,
        uint256 shortStrike
    ) public {
        vm.assume(tokenType < 4);
        vm.assume(productId > 0);

        uint256 id =
            TokenIdUtil.getTokenId(TokenType(tokenType), productId, uint64(expiry), uint64(longStrike), uint64(shortStrike));
        (TokenType _tokenType, uint40 _productId, uint64 _expiry, uint64 _longStrike, uint64 _shortStrike) =
            TokenIdUtil.parseTokenId(id);

        assertEq(tokenType, uint8(_tokenType));
        assertEq(productId, _productId);
        assertEq(uint64(expiry), _expiry);
        assertEq(uint64(longStrike), _longStrike);
        assertEq(uint64(shortStrike), _shortStrike);
    }

    function testReserveFormatAndParseAreMirrored(uint32 leveragePCT, uint32 barrierId) public {
        uint64 reserve = TokenIdUtil.getReserve(leveragePCT, barrierId);
        (uint32 _leveragePCT, uint32 _barrierId) = TokenIdUtil.parseReserve(reserve);

        assertEq(leveragePCT, _leveragePCT);
        assertEq(barrierId, _barrierId);
    }

    function testReserveGetAndParseAreMirrored(uint256 leveragePCT, uint256 barrierId) public {
        uint64 reserve = TokenIdUtil.getReserve(uint32(leveragePCT), uint32(barrierId));
        (uint32 _leveragePCT, uint32 _barrierId) = TokenIdUtil.parseReserve(reserve);

        assertEq(uint32(leveragePCT), _leveragePCT);
        assertEq(uint32(barrierId), _barrierId);
    }

    function testBarrierIdFormatAndParseAreMirrored(
        uint16 barrierPCT,
        BarrierObservationFrequencyType observationFrequency,
        BarrierTriggerType triggerType,
        BarrierExerciseType exerciseType
    ) public {
        vm.assume(barrierPCT > 0);
        vm.assume(observationFrequency <= type(BarrierObservationFrequencyType).max);
        vm.assume(triggerType <= type(BarrierTriggerType).max);
        vm.assume(exerciseType <= type(BarrierExerciseType).max);

        uint32 id = TokenIdUtil.getBarrierId(barrierPCT, observationFrequency, triggerType, exerciseType);
        (
            uint16 _barrierPCT,
            BarrierObservationFrequencyType _observationFrequency,
            BarrierTriggerType _triggerType,
            BarrierExerciseType _exerciseType
        ) = TokenIdUtil.parseBarrierId(id);

        assertEq(barrierPCT, _barrierPCT);
        assertEq(uint8(observationFrequency), uint8(_observationFrequency));
        assertEq(uint8(triggerType), uint8(_triggerType));
        assertEq(uint8(exerciseType), uint8(_exerciseType));
    }

    function testBarrierIdGetAndParseAreMirrored(
        uint256 barrierPCT,
        BarrierObservationFrequencyType observationFrequency,
        BarrierTriggerType triggerType,
        BarrierExerciseType exerciseType
    ) public {
        vm.assume(barrierPCT > 0);
        vm.assume(observationFrequency <= type(BarrierObservationFrequencyType).max);
        vm.assume(triggerType <= type(BarrierTriggerType).max);
        vm.assume(exerciseType <= type(BarrierExerciseType).max);

        uint32 id = TokenIdUtil.getBarrierId(uint16(barrierPCT), observationFrequency, triggerType, exerciseType);
        (
            uint16 _barrierPCT,
            BarrierObservationFrequencyType _observationFrequency,
            BarrierTriggerType _triggerType,
            BarrierExerciseType _exerciseType
        ) = TokenIdUtil.parseBarrierId(id);

        assertEq(uint16(barrierPCT), _barrierPCT);
        assertEq(uint8(observationFrequency), uint8(_observationFrequency));
        assertEq(uint8(triggerType), uint8(_triggerType));
        assertEq(uint8(exerciseType), uint8(_exerciseType));
    }
}
