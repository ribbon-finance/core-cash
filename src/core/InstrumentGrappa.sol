// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imported contracts and libraries
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

// interfaces
import {ICashOptionToken} from "../interfaces/ICashOptionToken.sol";
import {IMarginEngine} from "../interfaces/IMarginEngine.sol";

// libraries
import {OptionBalanceUtil} from "../libraries/OptionBalanceUtil.sol";
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
    using OptionBalanceUtil for OptionBalance[];
    using FixedPointMathLib for uint256;
    using NumberUtil for uint256;
    using ProductIdUtil for uint40;
    using SafeCast for uint256;
    using TokenIdUtil for uint256;

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

    event OptionSettled(
        address account, uint16 participationPCT, uint32 barrierId, uint256 tokenId, uint256 amountSettled, uint256 payout
    );
    event InstrumentRegistered(uint256 id);

    /*///////////////////////////////////////////////////////////////
              Constructor for implementation Contract
    //////////////////////////////////////////////////////////////*/

    /// @dev set immutables in constructor
    /// @dev also set the implementation contract to initialized = true
    constructor(address _optionToken, address _instrumentToken) Grappa(_optionToken) initializer {
        instrumentToken = ICashOptionToken(_instrumentToken);
    }

    /**
     * @dev register an instrument
     * @param _instrument Instrument to register
     * @return id instrument ID
     */
    function registerInstrument(Instrument calldata _instrument) external returns (uint256 id) {
        _isValidInstrumentToRegister(_instrument);

        id = InstrumentIdUtil.getInstrumentId(_instrument);

        if (instruments[id].options.length == 0) revert GP_InstrumentAlreadyRegistered();

        instruments[id] = _instrument;

        emit InstrumentRegistered(id);
    }

    /*///////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev parse instrument id into composing features, coupons, options
     * @param _instrumentId instrument id`
     */
    function getDetailFromInstrumentId(uint256 _instrumentId)
        public
        view
        returns (address engine, bool isReverse, uint32 autocallBarrierId, uint256 coupons, Option[] memory options)
    {
        Instrument memory _instrument = instruments[_instrumentId];
        engine = engines[_instrument.engineId];
        (isReverse, autocallBarrierId) = getDetailFromAutocallId(_instrument.autocallId);
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
        external
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
     * @dev get instrument id from autocall id, coupons, options array
     * @dev       function will still return even if instrument is not registered
     * @param _instrument Instrument
     * @return id instrument ID
     */
    function getInstrumentId(Instrument calldata _instrument) external pure returns (uint256 id) {
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
        returns (Balance[] memory payouts)
    {
        // Settle Instrument

        // getPayout
        // burn options
        // pay cash value

        // _settleAutocall()
        // _settleCoupons()
        // _settleOptions()

        Instrument memory _instrument = instruments[_instrumentId];
    }

    /* =====================================
     *          Internal Functions
     * ====================================**/

    /**
     * @dev make sure that the instrument make sense
     */
    function _isValidInstrumentToRegister(Instrument calldata _instrument) internal view {
        // TODO
    }

    /**
     * @notice burn option token and get out cash value at expiry
     *
     * @param _account  who to settle for
     * @param _option   option
     * @param _amount   amount to settle
     */
    function _settleOption(address _account, Option calldata _option, uint256 _amount) internal returns (uint256) {
        (address engine, address collateral, uint256 payout) = _getPayout(_option, _amount.toUint64());

        emit OptionSettled(_account, _option.participationPCT, _option.barrierId, _option.tokenId, _amount, payout);

        optionToken.burnGrappaOnly(_account, _option.tokenId, _amount);

        IMarginEngine(engine).payCashValue(collateral, _account, payout);

        return payout;
    }

    /**
     * @dev calculate the payout for instruments
     *
     * @param _instrumentId instrument id
     * @param _amount   amount to settle
     *
     * @return payout
     */
    function _getInstrumentPayout(uint256 _instrumentId, uint64 _amount) internal view returns (uint256 payout) {
        uint256 payoutPerInstrument;
        (payoutPerInstrument) = _getPayoutPerInstrument(_instrumentId);
        payout = payoutPerInstrument * _amount;
        unchecked {
            payout = payout / UNIT;
        }
    }

    /**
     * @dev calculate the payout for one option token
     *
     * @param _option  option struct
     * @param _amount   amount to settle
     *
     * @return engine engine to settle
     * @return collateral asset to settle in
     * @return payout amount paid
     *
     */
    function _getPayout(Option calldata _option, uint64 _amount)
        internal
        view
        returns (address engine, address collateral, uint256 payout)
    {
        uint256 payoutPerOption;
        (engine, collateral, payoutPerOption) = _getPayoutPerOption(_option);
        payout = payoutPerOption * _amount;
        unchecked {
            payout = payout / UNIT;
        }
    }

    /**
     * @dev calculate the payout for one instrument token
     *
     * @param _instrumentId  instrument id
     * @return payoutPerInstrument amount paid
     *
     */
    function _getPayoutPerInstrument(uint256 _instrumentId) internal view returns (OptionBalance[] memory) {
        Instrument memory _instrument = instruments[_instrumentId];
        uint40 autocallId = _instrument.autocallId;
        uint256 coupons = _instrument.coupons;
        Option[] memory options = _instrument.options;

        //TODO

        for (uint256 i = 0; i < MAX_COUPON_CONSTRUCTION; i++) {}

        return (0);
    }

    /**
     * @dev calculate the payout for one option token
     *
     * @param _option  option struct
     *
     * @return engine engine to settle
     * @return collateral asset to settle in
     * @return payoutPerOption amount paid
     *
     */
    function _getPayoutPerOption(Option calldata _option) internal view returns (address, address, uint256) {
        (address engine, address collateral, uint256 payoutPerOption) = _getPayoutPerToken(_option.tokenId);
        //TODO (add participation, barrier pct update)
        return (engine, collateral, payoutPerOption);
    }

    /**
     * @dev add an entry to array of OptionBalance
     * @param payouts existing payout array
     * @param tokenId new tokendId
     * @param payout new payout
     */
    function _addToPayouts(OptionBalance[] memory payouts, uint256 tokenId, uint256 payout)
        internal
        pure
        returns (OptionBalance[] memory)
    {
        if (payout == 0) return payouts;

        (bool found, uint256 index) = payouts.indexOf(TokenIdUtil.parseEngineId(tokenId), TokenIdUtil.parseCollateralId(tokenId));
        if (!found) {
            payouts = payouts.append(OptionBalance(tokenId, payout.toUint80()));
        } else {
            payouts[index].amount += payout.toUint80();
        }

        return payouts;
    }
}
