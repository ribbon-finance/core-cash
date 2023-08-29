// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracleDisputable} from "./PythOracleDisputable.sol";

// abstract
import {InstrumentOracle} from "./abstract/InstrumentOracle.sol";

// constants and types
import "./errors.sol";

/**
 * @title InstrumentPythOracleDisputable
 * @dev implementes barrier related logic for instruments
 */
contract InstrumentPythOracleDisputable is PythOracleDisputable, InstrumentOracle {
    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth) PythOracleDisputable(_owner, _pyth) {}

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * This function can be used to report a price and update a barrier in a single transaction. It is privileged since it involves a barrier update.
     * @param _pythUpdateData Pyth update data for the assets to report a price for
     * @param _priceIds Pyth price feed IDs (https://pyth.network/developers/price-feed-ids) to be updated, and should match those parsed from _pythUpdateData
     * @param _timestamp The timestamp to write the price and barrier update for
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _barrierUnderlyerAddresses Since this is a priveleged function, we just use this as a sanity check to ensure all barrier updates have a price set for these corresponding addresses. If using a non-stable quote asset, you should set both (e.g. ETH and USDC). If using a stable asset you only need to set the base asset (e.g. ETH).
     */
    function reportPrice(
        bytes[] calldata _pythUpdateData,
        bytes32[] calldata _priceIds,
        uint64 _timestamp,
        uint256 _instrumentId,
        uint32 _barrierId,
        address[] calldata _barrierUnderlyerAddresses
    ) external payable onlyOwner {
        if (_pythUpdateData.length != _priceIds.length || _priceIds.length != _barrierUnderlyerAddresses.length) {
            revert PY_ReportArgumentsLengthError();
        }
        reportPrice(_pythUpdateData, _priceIds, _timestamp);
        updateBarrier(_instrumentId, _barrierId, _timestamp, _barrierUnderlyerAddresses);
    }

    /**
     * Updates the breach timestamp of a barrier. It is public because we may need to update a barrier when the underlying price has already been reported.
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _timestamp The timestamp at which an update occurs. This could be a barrier breach, or just a general observation.
     * @param _barrierUnderlyerAddresses We use this as a sanity check to ensure all barrier updates have a price set for these corresponding addresses.
     * The price of the underlyer and strike asset at this timestamp should be used to verify.
     */
    function updateBarrier(
        uint256 _instrumentId,
        uint32 _barrierId,
        uint256 _timestamp,
        address[] calldata _barrierUnderlyerAddresses
    ) public override onlyOwner {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (_timestamp == 0) revert IO_InvalidTimestamp();
        uint256[] memory updates = barrierUpdates[_instrumentId][_barrierId];
        if (updates.length > 0) {
            uint256 lastTimestamp = updates[updates.length - 1];
            if (_timestamp < lastTimestamp) revert IO_InvalidTimestamp();
        }
        for (uint256 i = 0; i < _barrierUnderlyerAddresses.length; i++) {
            address currentAddress = _barrierUnderlyerAddresses[i];
            HistoricalPrice memory data = historicalPrices[currentAddress][_timestamp];
            if (data.reportAt == 0) revert OC_PriceNotReported();
        }
        barrierUpdates[_instrumentId][_barrierId].push(_timestamp);
        emit BarrierUpdated(_instrumentId, _barrierId, _timestamp);
    }
}
