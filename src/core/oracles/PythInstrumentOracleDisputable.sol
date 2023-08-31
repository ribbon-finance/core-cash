// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracleDisputable} from "./PythOracleDisputable.sol";

// abstract
import {InstrumentOracle} from "./abstract/InstrumentOracle.sol";

// constants and types
import "./errors.sol";

/**
 * @title PythInstrumentOracleDisputable
 * @dev implementes barrier related logic for instruments
 */
contract PythInstrumentOracleDisputable is PythOracleDisputable, InstrumentOracle {
    /*///////////////////////////////////////////////////////////////
                                Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, address _pyth, bytes32[] memory _initialFeedIds, address[] memory _initialBaseAddresses)
        PythOracleDisputable(_owner, _pyth, _initialFeedIds, _initialBaseAddresses)
    {}

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * This function can be used to report a price and update a barrier in a single transaction. It is privileged since it involves a barrier update.
     * @param _pythUpdateData Pyth update data for the assets to report a price for
     * @param _priceIds Pyth price feed IDs (https://pyth.network/developers/price-feed-ids) to be updated, and should match those parsed from _pythUpdateData
     * @param _timestamp The timestamp to write the price and barrier update for
     * @param _instrumentIds Array of Grappa intrumentIds to be updated
     * @param _barrierIds Array of Grappa barrierIds to be updated
     * @param _barrierUnderlyerAddresses Since this is a priveleged function, we just use this as a sanity check to ensure all barrier updates have a price set for these corresponding addresses. If using a non-stable quote asset, you should set both (e.g. ETH and USDC). If using a stable asset you only need to set the base asset (e.g. ETH).
     */
    function reportPrice(
        bytes[] calldata _pythUpdateData,
        bytes32[] calldata _priceIds,
        uint64 _timestamp,
        uint256[] calldata _instrumentIds,
        uint32[] calldata _barrierIds,
        address[] calldata _barrierUnderlyerAddresses
    ) external payable onlyOwner {
        if (_priceIds.length != _barrierUnderlyerAddresses.length) {
            revert OC_ArgumentsLengthError();
        }
        reportPrice(_pythUpdateData, _priceIds, _timestamp);
        updateBarrier(_instrumentIds, _barrierIds, _timestamp, _barrierUnderlyerAddresses);
    }

    /**
     * Updates the breach timestamp of a barrier. It is public because we may need to update a barrier when the underlying price has already been reported.
     * @param _instrumentIds Array of Grappa intrumentIds to be updated
     * @param _barrierIds Array of Grappa barrierIds to be updated
     * @param _timestamp The timestamp at which an update occurs. This could be a barrier breach, or just a general observation.
     * @param _barrierUnderlyerAddresses We use this as a sanity check to ensure all barrier updates have a price set for these corresponding addresses.
     * The price of the underlyer and strike asset at this timestamp should be used to verify.
     */
    function updateBarrier(
        uint256[] calldata _instrumentIds,
        uint32[] calldata _barrierIds,
        uint256 _timestamp,
        address[] calldata _barrierUnderlyerAddresses
    ) public override onlyOwner {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (_timestamp == 0) revert IO_InvalidTimestamp();
        if (_instrumentIds.length == 0 || _instrumentIds.length != _barrierIds.length || _barrierUnderlyerAddresses.length == 0) {
            revert OC_ArgumentsLengthError();
        }
        for (uint256 i = 0; i < _barrierUnderlyerAddresses.length; i++) {
            address currentAddress = _barrierUnderlyerAddresses[i];
            HistoricalPrice memory data = historicalPrices[currentAddress][_timestamp];
            if (data.reportAt == 0) revert OC_PriceNotReported();
        }
        for (uint256 i = 0; i < _barrierIds.length; i++) {
            uint256[] memory updates = barrierUpdates[_instrumentIds[i]][_barrierIds[i]];
            if (updates.length > 0) {
                uint256 lastTimestamp = updates[updates.length - 1];
                if (_timestamp < lastTimestamp) revert IO_InvalidTimestamp();
            }
            barrierUpdates[_instrumentIds[i]][_barrierIds[i]].push(_timestamp);
            emit BarrierUpdated(_instrumentIds[i], _barrierIds[i], _timestamp);
        }
    }
}
