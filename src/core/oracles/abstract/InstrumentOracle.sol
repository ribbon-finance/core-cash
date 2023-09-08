// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract InstrumentOracle {
    // instrumentId => barrierId => barrierUpdate
    // this is used to record the first continuous barrier breach we observe
    mapping(uint256 => mapping(uint32 => uint256)) public barrierBreaches;

    event BarrierBreachUpdated(uint256 instrumentId, uint32 barrierId, uint256 timestamp);

    /**
     * Updates the breach timestamp of a barrier
     * @param _instrumentIds Array of Grappa instrumentIds to be updated
     * @param _barrierIds Array of Grappa barrierIds to be updated
     * @param _timestamp The timestamp at which the barrier breach occurs.
     * @param _barrierUnderlyerAddresses We use this as a sanity check to ensure all barrier updates have a price set for these corresponding addresses.
     */
    function updateBarrier(
        uint256[] calldata _instrumentIds,
        uint32[] calldata _barrierIds,
        uint256 _timestamp,
        address[] calldata _barrierUnderlyerAddresses
    ) public virtual;
}
