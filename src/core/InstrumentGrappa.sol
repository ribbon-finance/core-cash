// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imported contracts and libraries
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

// interfaces
import {ICashOptionToken} from "../interfaces/ICashOptionToken.sol";
import {IMarginEngine} from "../interfaces/IMarginEngine.sol";

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
     * @param _barrierPCT percentage of the barrier relative to initial spot price
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
    function _isValidInstrumentToRegister(InstrumentIdUtil.InstrumentExtended memory _instrument) internal view {
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
        pure
        returns (uint256 payout)
    {
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
        (,, uint40 autocallId,, uint256 coupons, Option[] memory options) = getDetailFromInstrumentId(_instrumentId);

        uint256 expiry = Math.min(_autocallTimestamp(_instrumentId, autocallId), TokenIdUtil.parseExpiry(options[0].tokenId));

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

        //TODO
        // get initial spot price and multiply by coupon PCT

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
    function _getPayoutPerOption(uint256 _instrumentId, Option memory _option) internal view returns (uint256 payout) {
        (,, payout) = _getPayoutPerToken(_option.tokenId);
        // Apply participation
        payout = payout.mulDivDown(_option.participationPCT, HUNDRED_PCT);
        // Apply barrier
        payout = _payoutWithBarrier(_instrumentId, _option.barrierId, payout);
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

    /**
     * @dev add an entry to array of InstrumentComponentBalance
     * @param _instrumentId  instrument id
     * @param _barrierId barrier id
     * @param _payout payout
     */
    function _payoutWithBarrier(uint256 _instrumentId, uint32 _barrierId, uint256 _payout) internal pure returns (uint256) {
        // If (breached and knock out) or (not breached and knock in): 0
        // return _payout
        return 0;
    }

    /**
     * @dev add an entry to array of InstrumentComponentBalance
     * @param _instrumentId  instrument id
     * @param _autocallId autocall id
     * @return autocallTimestamp timestamp of autocall
     */
    function _autocallTimestamp(uint256 _instrumentId, uint40 _autocallId) internal pure returns (uint256 autocallTimestamp) {
        //TODO

        // (, uint32 barrierId) = getDetailFromAutocallId(autocallId);
        // (bool breached, bool finalized, bool timestamp) = IInstrumentOracle(oracles[instruments[_instrumentId].oracleId])isBarrierBreached(_instrumentId, barrierId)
        // uint256 expiry = breached && finalized ? timestamp : TokenIdUtil.parseExpiry(options[0].tokenId)
        autocallTimestamp = type(uint256).max;
    }
}
