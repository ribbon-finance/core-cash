// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PythOracleDisputable} from "./PythOracleDisputable.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

// interfaces
import {InstrumentOracle} from "./abstract/InstrumentOracle.sol";
import {IInstrumentGrappa} from "../../interfaces/IInstrumentGrappa.sol";

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

    constructor(address _owner, address _pyth, address _instrumentGrappaAddress) PythOracleDisputable(_owner, _pyth) InstrumentOracle(_instrumentGrappaAddress) {}

    /*///////////////////////////////////////////////////////////////
                            External Functions
    //////////////////////////////////////////////////////////////*/

    function isBarrierBreached(uint256 _instrumentId, uint32 _barrierId) external override view returns (bool isBreached, bool isFinalized) {
        (uint16 barrierPCT, BarrierExerciseType exerciseType, uint64 period, uint64 expiry, address underlying, address strike) = _getBarrierInformation(_instrumentId, _barrierId);
        if (exerciseType == BarrierExerciseType.EUROPEAN) {
            return _isEuropeanBarrierBreached(expiry, period, barrierPCT, underlying, strike);
        } else {
            return _isAmericanBarrierBreached(_instrumentId, _barrierId, underlying, strike);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Privileged Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * Updates the breach timestamp of an american barrier 
     * @param _instrumentId Grappa intrumentId
     * @param _barrierId Grappa barrierId
     * @param _timestamp The timestamp at which the breach occured. The price of the underlyer and strike asset at the provided timestamp should be used to verify.
     */
    function updateAmericanBarrier(uint256 _instrumentId, uint32 _barrierId, uint256 _timestamp) external override onlyOwner {
        if (_timestamp > block.timestamp) revert OC_CannotReportForFuture();
        if (_timestamp == 0) {
            // By default we only update barriers on a breach (timestamp 0 to timestamp !0)
            // So this special case means we're overwritting the breach and setting the barrier to be unbreached
            americanBarrierBreaches[_instrumentId][_barrierId] = _timestamp;
            emit AmericanBarrierUpdated(_instrumentId, _barrierId, _timestamp);
            return;
        }
        (uint16 barrierPCT, , uint64 period, uint64 expiry, address underlying, address strike) = _getBarrierInformation(_instrumentId, _barrierId);
        (uint256 price, ) = _getPriceAtTimestamp(underlying, strike, _timestamp);
        (uint256 spotPriceAtCreation,) = _getPriceAtTimestamp(underlying, strike, expiry - period);
        if (spotPriceAtCreation == 0) revert OC_PriceNotReported();
        // TODO is there a better way to do the rounding? This rounding favours one case over another but should cancel out on the whole?
        uint256 barrierBreachPrice = spotPriceAtCreation.mulDivUp(barrierPCT, 100);
        bool americanBarrierBreached = _compareBarrierPrices(barrierBreachPrice, price, barrierPCT);
        if (!americanBarrierBreached) revert IO_AmericanBarrierNotBreached();
        americanBarrierBreaches[_instrumentId][_barrierId] = _timestamp;
        emit AmericanBarrierUpdated(_instrumentId, _barrierId, _timestamp);
    }


    /*///////////////////////////////////////////////////////////////
                            Admin Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev set the InstrumentGrappa contract for this oracle
     * @param _instrumentGrappa the address of the InstrumentGrappa contract
     */
    function setInstrumentGrappa(address _instrumentGrappa) external override onlyOwner {
        if (_instrumentGrappa == address(0)) revert OC_ZeroAddress();
        instrumentGrappa = IInstrumentGrappa(_instrumentGrappa);
        emit InstrumentGrappaUpdated(_instrumentGrappa);
    }

    /*///////////////////////////////////////////////////////////////
                            Internal functions
    //////////////////////////////////////////////////////////////*/

    function _getBarrierInformation(uint256 _instrumentId, uint32 _barrierId) internal view returns (uint16 barrierPCT, BarrierExerciseType exerciseType, uint64 period, uint64 expiry, address underlying, address strike) {
        (uint16 _barrierPCT, , , BarrierExerciseType _exerciseType) = instrumentGrappa.getDetailFromBarrierId(_barrierId);
        (uint64 _period, , , , Option[] memory options) = instrumentGrappa.getDetailFromInstrumentId(_instrumentId);
        (, uint40 productId, uint64 _expiry, , ) = instrumentGrappa.getDetailFromTokenId(options[0].tokenId);
        (, , address _underlying, , address _strike, , ,) = instrumentGrappa.getDetailFromProductId(productId);
        return (_barrierPCT, _exerciseType, _period, _expiry, _underlying, _strike);
    }

    function _isAmericanBarrierBreached(uint256 _instrumentId, uint32 _barrierId, address underlying, address strike) internal view returns (bool isBreached, bool isFinalized) {
        uint256 americanBarrierBreachTimestamp = americanBarrierBreaches[_instrumentId][_barrierId];
        if (americanBarrierBreachTimestamp == 0) {
            return (false, true);
        } else {
            (, bool isAmericanBarrierBreachPriceFinalized) = _getPriceAtTimestamp(underlying, strike, americanBarrierBreachTimestamp);
            return (true, isAmericanBarrierBreachPriceFinalized);
        }
    }

    function _isEuropeanBarrierBreached(uint64 expiry, uint64 period, uint16 barrierPCT, address underlying, address strike) internal view returns (bool isBreached, bool isFinalized) {
        (uint256 spotPriceAtCreation, bool isSpotPriceAtCreationFinalized) = _getPriceAtTimestamp(underlying, strike, expiry - period);
        if (spotPriceAtCreation == 0) revert OC_PriceNotReported();
        (uint256 expiryPrice, bool isExpiryPriceFinalized) = _getPriceAtTimestamp(underlying, strike, expiry);
        if (expiryPrice == 0) revert OC_PriceNotReported();
        bool europeanBarrierFinalized = isSpotPriceAtCreationFinalized && isExpiryPriceFinalized;
        // TODO is there a better way to do the rounding? This rounding favours one case over another but should cancel out on the whole?
        uint256 barrierBreachPrice = spotPriceAtCreation.mulDivUp(barrierPCT, 100);
        bool europeanBarrierBreached = _compareBarrierPrices(barrierBreachPrice, expiryPrice, barrierPCT);
        return (europeanBarrierBreached, europeanBarrierFinalized);
    }

    function _compareBarrierPrices(uint256 _barrierBreachPrice, uint256 _comparisonPrice, uint16 _barrierPCT) internal pure returns (bool isBreached) {
        if (_barrierPCT < 100) {
            return _comparisonPrice < _barrierBreachPrice;
        } else {
            return _comparisonPrice > _barrierBreachPrice;
        }
    }
}
