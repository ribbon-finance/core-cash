// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract InstrumentOracle {
    // instrumentId => barrierId => barrierUpdates
    mapping(uint256 => mapping(uint32 => uint256[])) public barrierUpdates;

    event BarrierUpdated(uint256 instrumentId, uint32 barrierId, uint256 timestamp);

    /**
     * Updates the breach timestamp of a barrier
     * @param _instrumentIds Array of Grappa instrumentIds to be updated
     * @param _barrierIds Array of Grappa barrierIds to be updated
     * @param _timestamp The timestamp at which an update occurs. This could be a barrier breach, or just a general observation.
     * @param _barrierUnderlyerAddresses We use this as a sanity check to ensure all barrier updates have a price set for these corresponding addresses.
     */
    function updateBarrier(
        uint256[] calldata _instrumentIds,
        uint32[] calldata _barrierIds,
        uint256 _timestamp,
        address[] calldata _barrierUnderlyerAddresses
    ) public virtual;
}
