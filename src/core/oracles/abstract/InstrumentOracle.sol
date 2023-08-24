// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IInstrumentGrappa} from "../../../interfaces/IInstrumentGrappa.sol";
import "../../../config/errors.sol";


abstract contract InstrumentOracle {

    IInstrumentGrappa public instrumentGrappa;

    // instrumentId => barrierId => breachTimestamp
    mapping(uint256 => mapping(uint32 => uint256)) public americanBarrierBreaches;

    event AmericanBarrierUpdated(uint256 instrumentId, uint32 barrierId, uint256 timestamp);

    event InstrumentGrappaUpdated(address newInstrumentGrappa);

    constructor(address _instrumentGrappaAddress) {
        // solhint-disable-next-line reason-string
        if (_instrumentGrappaAddress == address(0)) revert OC_ZeroAddress();
        instrumentGrappa = IInstrumentGrappa(_instrumentGrappaAddress);
    }

    /**
     * Updates the breach timestamp of an american barrier 
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _timestamp The timestamp at which the breach occured. The price of the underlyer and strike asset at the provided timestamp should be used to verify.
     */
    function updateAmericanBarrier(uint256 _instrumentId, uint32 _barrierId, uint256 _timestamp) external virtual;

    /**
     * @dev Checks if a given barrier has been breached
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @return isBreached When barrier < 100 pct, true if price drops below the barrier price and false otherwise. Vice versa for when barrier > 100 pct.
     * @return isFinalized Checks if underlying and strike asset's prices used to check the barrier breach have been finalized.
     */
    function isBarrierBreached(uint256 _instrumentId, uint32 _barrierId) external virtual view returns (bool isBreached, bool isFinalized);

    /**
     * @dev Set the InstrumentGrappa contract for this oracle
     * @param _instrumentGrappa The address of the InstrumentGrappa contract
     */
    function setInstrumentGrappa(address _instrumentGrappa) external virtual;

}
