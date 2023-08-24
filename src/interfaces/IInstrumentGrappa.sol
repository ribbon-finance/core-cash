// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../config/types.sol";
import "./IGrappa.sol";

interface IInstrumentGrappa is IGrappa {
    function getDetailFromInstrumentId(uint256 _instrumentId)
        external
        view
        returns (uint64 period, uint8 engine, uint40 autocallId, uint256 coupons, Option[] memory options);

    function getDetailFromBarrierId(uint32 _barrierId)
        external
        pure
        returns (
            uint16 barrierPCT,
            BarrierObservationFrequencyType observationFrequency,
            BarrierTriggerType triggerType,
            BarrierExerciseType exerciseType
        );
}
