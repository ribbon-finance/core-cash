// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imported contracts and libraries
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

// interfaces
import {ICashOptionToken} from "../interfaces/ICashOptionToken.sol";
import {IMarginEngine} from "../interfaces/IMarginEngine.sol";
import {IInstrumentOracle} from "../interfaces/IInstrumentOracle.sol";

// libraries
import {InstrumentComponentBalanceUtil} from "../libraries/InstrumentComponentBalanceUtil.sol";
import {MoneynessLib} from "../libraries/MoneynessLib.sol";
import {NumberUtil} from "../libraries/NumberUtil.sol";
import {ProductIdUtil} from "../libraries/ProductIdUtil.sol";
import {TokenIdUtil} from "../libraries/TokenIdUtil.sol";
import {InstrumentIdUtil} from "../libraries/InstrumentIdUtil.sol";

// constants and types
import "../config/types.sol";
import "../config/enums.sol";
import "../config/constants.sol";
import "../config/errors.sol";

import {Grappa} from "./Grappa.sol";

contract InstrumentGrappa is Grappa {
    using InstrumentComponentBalanceUtil for InstrumentComponentBalance[];
    using FixedPointMathLib for uint256;
    using NumberUtil for uint256;
    using ProductIdUtil for uint40;
    using SafeCast for uint256;
    using TokenIdUtil for uint256;
    using Math for uint256;

    /// @dev optionToken address
    ICashOptionToken public immutable instrumentToken;

    /*///////////////////////////////////////////////////////////////
                       State Variables V1
    //////////////////////////////////////////////////////////////*/

    /// @dev instrumentId => instrument
    mapping(uint256 => Instrument) public instruments;

    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event InstrumentComponentSettled(address account, uint8 index, bool isCoupon, uint80 payout);
    event InstrumentRegistered(uint256 id);

    /*///////////////////////////////////////////////////////////////
              Constructor for implementation Contract
    //////////////////////////////////////////////////////////////*/

    /// @dev set immutables in constructor
    /// @dev also set the implementation contract to initialized = true
    constructor(address _optionToken, address _instrumentToken) Grappa(_optionToken) {
        instrumentToken = ICashOptionToken(_instrumentToken);
    }

    /**
     * @dev register an instrument
     * @param _instrument Instrument to register
     * @return id instrument ID
     */
    function registerInstrument(InstrumentIdUtil.InstrumentExtended calldata _instrument) external returns (uint256 id) {
        _isValidInstrumentToRegister(_instrument);

        Instrument memory sInstrument = InstrumentIdUtil.serialize(_instrument);

        id = InstrumentIdUtil.getInstrumentId(sInstrument);

        if (instruments[id].options.length > 0) revert GP_InstrumentAlreadyRegistered();

        instruments[id].oracleId = sInstrument.oracleId;
        instruments[id].engineId = sInstrument.engineId;
        instruments[id].autocallId = sInstrument.autocallId;
        instruments[id].period = sInstrument.period;
        instruments[id].coupons = sInstrument.coupons;

        for (uint8 i; i < _instrument.options.length;) {
            instruments[id].options.push(sInstrument.options[i]);
            unchecked {
                ++i;
            }
        }

        emit InstrumentRegistered(id);
    }

    /*///////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev serialize an instrument
     * @param _instrument Instrument to serialize
     * @return instrument struct
     */
    function serialize(InstrumentIdUtil.InstrumentExtended calldata _instrument)
        external
        pure
        returns (Instrument memory instrument)
    {
        instrument = InstrumentIdUtil.serialize(_instrument);
    }

    /**
     * @dev parse instrument id into composing features, coupons, options
     * @param _instrumentId instrument id
     */
    function getDetailFromInstrumentId(uint256 _instrumentId)
        public
        view
        returns (uint8 oracleId, uint8 engineId, uint40 autocallId, uint64 period, uint256 coupons, Option[] memory options)
    {
        Instrument memory _instrument = instruments[_instrumentId];
        oracleId = _instrument.oracleId;
        engineId = _instrument.engineId;
        autocallId = _instrument.autocallId;
        period = _instrument.period;
        coupons = _instrument.coupons;
        options = _instrument.options;
    }

    function getInitialSpotPrice(uint256 _instrumentId) external view returns (uint256 price) {
        (uint64 _period, uint64 _expiry, address _oracle, address _underlying, address _strike) = _getOracleInfo(_instrumentId);
        return _getOraclePrice(_oracle, _underlying, _strike, _expiry - _period);
    }

    /**
     * @dev parse autocall id into composing autocall details
     * @param _autocallId autocall id
     */
    function getDetailFromAutocallId(uint40 _autocallId) public pure returns (bool isReverse, uint32 barrierId) {
        return InstrumentIdUtil.parseAutocallId(_autocallId);
    }

    /**
     * @dev parse coupon id into composing coupon details
     * @param _coupon one coupon
     */
    function getDetailFromCouponId(uint64 _coupon)
        external
        pure
        returns (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId)
    {
        return InstrumentIdUtil.parseCouponId(_coupon);
    }

    /**
     * @dev parse coupon id into composing coupon details
     * @param _coupons all coupons
     * @param _index index of specific coupon
     */
    function getDetailFromCouponId(uint256 _coupons, uint256 _index)
        public
        pure
        returns (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId)
    {
        return InstrumentIdUtil.parseCouponId(_coupons, _index);
    }

    /**
     * @dev parse barrier id into composing barrier details
     * @param _barrierId barrier id
     */
    function getDetailFromBarrierId(uint32 _barrierId)
        public
        pure
        returns (
            uint16 barrierPCT,
            BarrierObservationFrequencyType observationFrequency,
            BarrierTriggerType triggerType,
            BarrierExerciseType exerciseType
        )
    {
        return InstrumentIdUtil.parseBarrierId(_barrierId);
    }

    /**
     * @dev get expiry of instrument id
     * @param _instrumentId instrument id
     */
    function getExpiry(uint256 _instrumentId) public view returns (uint64 expiry) {
        return InstrumentIdUtil.getExpiry(instruments[_instrumentId]);
    }

    /**
     * @dev parse barrier observation frequency type
     * @param _observationFrequency observation frequency enum
     */
    function convertBarrierObservationFrequencyType(BarrierObservationFrequencyType _observationFrequency)
        public
        pure
        returns (uint256 frequency)
    {
        frequency = InstrumentIdUtil.convertBarrierObservationFrequencyType(_observationFrequency);
    }

    /**
     * @dev get instrument id from autocall id, coupons, options array
     * @dev       function will still return even if instrument is not registered
     * @param _instrument Instrument struct
     * @return id instrument ID
     */
    function getInstrumentId(Instrument calldata _instrument) external pure returns (uint256 id) {
        id = InstrumentIdUtil.getInstrumentId(_instrument);
    }

    /**
     * @dev get instrument id from autocall id, coupons, options array
     * @dev       function will still return even if instrument is not registered
     * @param _instrument InstrumentExtended
     * @return id instrument ID
     */
    function getInstrumentId(InstrumentIdUtil.InstrumentExtended memory _instrument) external pure returns (uint256 id) {
        id = InstrumentIdUtil.getInstrumentId(_instrument);
    }

    /**
     * @dev get autocall id from isReverse, barrierId
     * @param _isReverse is reverse
     * @param _barrierId barrier id
     */
    function getAutocallId(bool _isReverse, uint32 _barrierId) external pure returns (uint256 id) {
        id = InstrumentIdUtil.getAutocallId(_isReverse, _barrierId);
    }

    /**
     * @dev get coupon id from coupon pct, num installments, coupon type, barrier id
     * @param _couponPCT coupon percentage of notional
     * @param _numInstallements number of installments
     * @param _couponType coupon type
     * @param _barrierId barrier id
     */
    function getCouponId(uint16 _couponPCT, uint16 _numInstallements, CouponType _couponType, uint32 _barrierId)
        external
        pure
        returns (uint64 id)
    {
        id = InstrumentIdUtil.getCouponId(_couponPCT, _numInstallements, _couponType, _barrierId);
    }

    /**
     * @dev get coupons from coupon array
     * @param _coupons coupons
     */
    function getCoupons(uint64[] calldata _coupons) external pure returns (uint256 coupons) {
        coupons = InstrumentIdUtil.getCoupons(_coupons);
    }

    /**
     * @notice    get barrier id from barrier pct, observation frequency, trigger type, exercise type
     * @param _barrierPCT percentage of the barrier relative to initial spot price in {UNIT_PERCENTAGE_DECIMALS} decimals
     * @param _observationFrequency frequency of barrier observations
     * @param _triggerType trigger type of the barrier
     * @param _exerciseType exercise type of the barrier
     */
    function getBarrierId(
        uint16 _barrierPCT,
        BarrierObservationFrequencyType _observationFrequency,
        BarrierTriggerType _triggerType,
        BarrierExerciseType _exerciseType
    ) external pure returns (uint32 id) {
        id = InstrumentIdUtil.getBarrierId(_barrierPCT, _observationFrequency, _triggerType, _exerciseType);
    }

    /**
     * @dev check if a barrier has been breached
     * @param _instrumentId instrument id
     * @param _barrierId barrier id
     * @return breaches Array of timestamps representing barrier breaches. Empty if barrier was not breached.
     */
    function getBarrierBreaches(uint256 _instrumentId, uint32 _barrierId) external pure returns (uint256[] memory breaches) {
        return _getBarrierBreaches(_instrumentId, _barrierId);
    }

    /**
     * @notice burn option token and get out cash value at expiry
     *
     * @param _account  who to settle for
     * @param _instrumentId   instrumentId
     * @param _amount   amount to settle
     */
    function settleInstrument(address _account, uint256 _instrumentId, uint256 _amount)
        external
        nonReentrant
        returns (InstrumentComponentBalance[] memory payouts)
    {
        uint8 instrumentEngineId = instruments[_instrumentId].engineId;

        // Settle Instrument
        payouts = getInstrumentPayout(_instrumentId, _amount);

        for (uint8 i; i < payouts.length;) {
            InstrumentComponentBalance memory payout = payouts[i];
            emit InstrumentComponentSettled(_account, payout.index, payout.isCoupon, payout.amount);

            if (!payout.isCoupon) {
                optionToken.burnGrappaOnly(engines[instrumentEngineId], payout.tokenId, _amount);
            }

            uint8 engineId = TokenIdUtil.parseEngineId(payout.tokenId);
            uint8 collateralId = TokenIdUtil.parseCollateralId(payout.tokenId);

            IMarginEngine(engines[engineId]).payCashValue(assets[collateralId].addr, _account, payout.amount);
            unchecked {
                ++i;
            }
        }

        instrumentToken.burnGrappaOnly(_account, _instrumentId, _amount);
    }

    /* =====================================
     *          Internal Functions
     * ====================================**/

    /**
     * @dev make sure that the instrument make sense
     */
    function _isValidInstrumentToRegister(InstrumentIdUtil.InstrumentExtended memory _instrument) internal pure {
        // TODO
    }

    /**
     * @dev calculate the payout for one option
     *
     * @param _instrumentId  instrument id
     * @param _option  option
     * @param _amount amount to settle
     *
     * @return payout amount paid
     *
     */
    function getOptionPayout(uint256 _instrumentId, Option memory _option, uint256 _amount)
        public
        view
        returns (uint256 payout)
    {
        if (instruments[_instrumentId].options.length == 0) revert GP_InstrumentNotRegistered();

        uint256 payoutPerOption;
        (payoutPerOption) = _getPayoutPerOption(_instrumentId, _option);
        payout = payoutPerOption * _amount;
        unchecked {
            payout = payout / UNIT;
        }
    }

    /**
     * @dev calculate the payout for one coupon
     *
     * @param _instrumentId  instrument id
     * @param _coupons  coupons
     * @param _index index
     * @param _amount amount to settle
     *
     * @return payout amount paid
     *
     */
    function getCouponPayout(uint256 _instrumentId, uint256 _coupons, uint256 _index, uint256 _amount)
        public
        view
        returns (uint256 payout)
    {
        if (instruments[_instrumentId].options.length == 0) revert GP_InstrumentNotRegistered();

        uint256 payoutPerCoupon;
        (payoutPerCoupon) = _getPayoutPerCoupon(_instrumentId, _coupons, _index);
        payout = payoutPerCoupon * _amount;
        unchecked {
            payout = payout / UNIT;
        }
    }

    /**
     * @dev calculate the payout for instruments
     *
     * @param _instrumentId  instrument id
     * @param _amount   amount to settle
     * @return payouts amounts paid
     *
     */
    function getInstrumentPayout(uint256 _instrumentId, uint256 _amount)
        public
        view
        returns (InstrumentComponentBalance[] memory payouts)
    {
        if (instruments[_instrumentId].options.length == 0) revert GP_InstrumentNotRegistered();

        (,,,, uint256 coupons, Option[] memory options) = getDetailFromInstrumentId(_instrumentId);

        // Add payouts of all the coupons
        for (uint8 i; i < MAX_COUPON_CONSTRUCTION;) {
            uint256 payout = getCouponPayout(_instrumentId, coupons, i, _amount);
            payouts = _addToPayouts(payouts, i, true, 0, payout);
            unchecked {
                ++i;
            }
        }

        // Add payouts of all the options
        for (uint8 i; i < options.length;) {
            Option memory option = options[i];
            uint256 payout = getOptionPayout(_instrumentId, option, _amount);
            payouts = _addToPayouts(payouts, i, false, option.tokenId, payout);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev calculate the payout for one coupon unit
     *
     * @param _instrumentId  instrument id
     * @param _coupons  coupons
     * @param _index  index within coupons
     *
     * @return payout amount paid
     *
     */
    function _getPayoutPerCoupon(uint256 _instrumentId, uint256 _coupons, uint256 _index)
        internal
        pure
        returns (uint256 payout)
    {
        (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId) =
            getDetailFromCouponId(_coupons, _index);

        // Apply early termination
        uint64 settleTime = _getSettleTime(_instrumentId);

        // Breach[] memory breaches = getBarrierBreaches(_instrumentId, barrierId);
        uint256 _numInstallements = 0; //breaches.length;

        // TODO require num installements match

        uint256 initialSpotPrice = 0; // TODO
        uint256 installment = (couponPCT * initialSpotPrice / HUNDRED_PCT) / _numInstallements;

        uint256 numPayouts = 0;
        uint256 latestPayout = 0;

        for (uint8 i; i < _numInstallements;) {
            uint256 barrierPayout = 0; // TODO take into account breach
            // if(breach.timestamp > settleTime) break; // TODO

            if (barrierPayout == 1) {
                numPayouts += 1;
                latestPayout = i;
            }

            unchecked {
                ++i;
            }
        }

        /**
         * NONE:            normal coupon
         * FIXED:           coupon barrier is 0, so will get every payout until termination
         * PHOENIX:         coupon barrier is above 0, so will get every coupon where
         *                  observation above barrier until termination
         * PHOENIX_MEMORY:  coupon barrier is above 0, so will get every coupon before
         *                  (and including) the latest observation above barrier until termination
         * VANILLA:         coupon barrier = autocall barrier + phoenix memory so will only get one coupon
         *
         * NOTE:            for FIXED, PHOENIX, PHOENIX_MEMORY, VANILLA the short autocall swap
         *                  (holder of instrument token) will get the inverse of payout for long autocall swap
         */
        if (couponType == CouponType.NONE) {
            payout = numPayouts * installment;
        } else if (couponType == CouponType.FIXED || couponType == CouponType.PHOENIX) {
            payout = (_numInstallements - numPayouts) * installment;
        } else {
            payout = (_numInstallements - latestPayout) * installment;
        }

        return 0;
    }

    /**
     * @dev calculate the payout for one option token
     *
     * @param _instrumentId  instrument id
     * @param _option  option struct
     *
     * @return payout payout per option
     *
     */
    function _getPayoutPerOption(uint256 _instrumentId, Option memory _option) internal view returns (uint256) {
        // Apply early termination
        if (_getSettleTime(_instrumentId) < TokenIdUtil.parseExpiry(_option.tokenId)) return 0;

        (,, uint256 payout) = _getPayoutPerToken(_option.tokenId);

        // Apply participation
        payout = payout.mulDivDown(_option.participationPCT, HUNDRED_PCT);
        // Apply barrier
        payout = payout * _getPayoutPerBarrier(_instrumentId, _option.barrierId);

        return payout;
    }

    /**
     * @dev Return 0 or 1
     * @param _instrumentId  instrument id
     * @param _barrierId barrier id
     */
    function _getPayoutPerBarrier(uint256 _instrumentId, uint32 _barrierId) internal pure returns (uint256) {
        if (_barrierId == 0) return 1;
        // (,, BarrierTriggerType triggerType, ) = parseBarrierId(_barrierId);
        // bool breached = true; //TODO: get whether was breached -- get the length
        //
        // bool knockedOut = _breached && _triggerType == BarrierTriggerType.KNOCK_OUT;
        // if(knockedOut) return 0;
        // bool notKnockedIn = !_breached && _triggerType == BarrierTriggerType.KNOCK_IN;
        // if(notKnockedIn) return 0;

        return 1;
    }

    /**
     * @dev get instrument settlement time
     * @param _instrumentId  instrument id
     * @return settleTime timestamp of settlement
     */
    function _getSettleTime(uint256 _instrumentId) internal pure returns (uint64) {
        //TODO

        // (,,uint40 autocallId,,) = getDetailFromInstrumentId(_instrumentId);
        // (, uint32 barrierId) = getDetailFromAutocallId(autocallId);
        // (bool breached, bool finalized, bool timestamp) = IInstrumentOracle(oracles[instruments[_instrumentId].oracleId]).isBarrierBreached(_instrumentId, barrierId)
        // uint256 expiry = breached && finalized ? timestamp : getExpiry(_instrumentId);
        // IS REVERSE CHECK
        return 0;
    }

    function _getBarrierBreaches(uint256 _instrumentId, uint32 _barrierId) internal view returns (uint256[] memory) {
        InstrumentIdUtil.BreachDetail memory details = _parseBreachDetail(_instrumentId, _barrierId);

        uint256 nObs = details.exerciseType == BarrierExerciseType.DISCRETE ? details.period / details.frequency : 1;
        uint256[] memory breaches = new uint256[](nObs);

        uint256 ts;

        if (details.exerciseType == BarrierExerciseType.EUROPEAN) {
            ts = details.expiry;
        } else if (details.exerciseType == BarrierExerciseType.CONTINUOUS) {
            ts = IInstrumentOracle(details.oracle).barrierBreaches(_instrumentId, _barrierId);
        } else {
            ts = details.expiry - details.period + details.frequency;
        }

        for (uint256 i = 0; i < nObs; i++) {
            if (ts == 0) break;
            uint256 price = _getOraclePrice(details.oracle, details.underlying, details.strike, ts);
            if (details.breachThreshold.isBreached(price, details.barrierPCT)) breaches[i] = ts;
            ts += details.frequency;
        }

        return breaches;
    }

    function _parseBreachDetail(uint256 _instrumentId, uint32 _barrierId)
        internal
        view
        returns (InstrumentIdUtil.BreachDetail memory details)
    {
        (uint16 _barrierPCT, BarrierObservationFrequencyType _observationFrequency,, BarrierExerciseType _exerciseType) =
            getDetailFromBarrierId(_barrierId);

        (uint64 _period, uint64 _expiry, address _oracle, address _underlying, address _strike) = _getOracleInfo(_instrumentId);

        return InstrumentIdUtil.BreachDetail({
            barrierPCT: _barrierPCT,
            breachThreshold: _getOraclePrice(_oracle, _underlying, _strike, _expiry - _period).mulDivUp(_barrierPCT, UNIT_PERCENTAGE),
            exerciseType: _exerciseType,
            period: _period,
            expiry: _expiry,
            oracle: _oracle,
            underlying: _underlying,
            strike: _strike,
            frequency: convertBarrierObservationFrequencyType(_observationFrequency)
        });
    }

    function _getOracleInfo(uint256 _instrumentId) internal view returns (uint64, uint64, address, address, address) {
        (,,, uint64 _period,, Option[] memory _options) = getDetailFromInstrumentId(_instrumentId);
        (, uint40 _productId, uint64 _expiry,,) = getDetailFromTokenId(_options[0].tokenId);
        (address _oracle,, address _underlying,, address _strike,,,) = getDetailFromProductId(_productId);
        return (_period, _expiry, _oracle, _underlying, _strike);
    }

    /**
     * @dev add an entry to array of InstrumentComponentBalance
     * @param _payouts existing payout array
     * @param _index index in coupons or options array
     * @param _isCoupon whether it is coupon (true) or option (false)
     * @param _tokenId token id
     * @param _payout new payout
     */
    function _addToPayouts(
        InstrumentComponentBalance[] memory _payouts,
        uint8 _index,
        bool _isCoupon,
        uint256 _tokenId,
        uint256 _payout
    ) internal pure returns (InstrumentComponentBalance[] memory) {
        if (_payout == 0) return _payouts;

        _payouts.append(InstrumentComponentBalance(_index, _isCoupon, _tokenId, _payout.toUint80()));

        return _payouts;
    }
}
