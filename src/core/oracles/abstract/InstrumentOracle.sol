// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract InstrumentOracle {
    // instrumentId => barrierId => barrierUpdates
    mapping(uint256 => mapping(uint32 => uint256[])) public barrierUpdates;

    event BarrierUpdated(uint256 instrumentId, uint32 barrierId, uint256 timestamp);

    /**
     * Updates the breach timestamp of a barrier
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _timestamp The timestamp at which an update occurs. This could be a barrier breach, or just a general observation.
     */
    function updateBarrier(uint256 _instrumentId, uint32 _barrierId, uint256 _timestamp) external virtual;
}
