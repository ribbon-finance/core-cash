// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracle} from "./PythOracle.sol";

// abstract
import {InstrumentOracle} from "./abstract/InstrumentOracle.sol";

// constants and types
import "./errors.sol";

/**
 * @title InstrumentPythOracleDisputable
 * @dev implementes barrier related logic for instruments
 */
contract InstrumentPythOracleDisputable is PythOracle, InstrumentOracle {
    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth) PythOracle(_owner, _pyth) {}

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * Updates the breach timestamp of a barrier
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _timestamp The timestamp at which an update occurs. This could be a barrier breach, or just a general observation.
     * The price of the underlyer and strike asset at this timestamp should be used to verify.
     */
    function updateBarrier(uint256 _instrumentId, uint32 _barrierId, uint256 _timestamp) external override onlyOwner {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (_timestamp == 0) revert IO_InvalidTimestamp();
        barrierUpdates[_instrumentId][_barrierId].push(_timestamp);
        emit BarrierUpdated(_instrumentId, _barrierId, _timestamp);
    }
}
