// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracleDisputable} from "./PythOracleDisputable.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

//libraries
import {InstrumentIdUtil} from "../../libraries/InstrumentIdUtil.sol";
import {TokenIdUtil} from "../../libraries/TokenIdUtil.sol";
// abstract
import {InstrumentOracle} from "./abstract/InstrumentOracle.sol";

// constants and types
import "./errors.sol";
import "../../config/types.sol";

/**
 * @title InstrumentPythOracleDisputable
 * @dev return base / quote price, with 6 decimals
 */
contract InstrumentPythOracleDisputable is PythOracleDisputable, InstrumentOracle {
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth) PythOracleDisputable(_owner, _pyth) {}

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
