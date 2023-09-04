// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imported contracts and libraries
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

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

    /// @dev optionToken address
    ICashOptionToken public immutable instrumentToken;

    /// @dev internal struct to bypass stack too deep issues
    struct BreachDetail {
        uint16 barrierPCT;
        BarrierExerciseType exerciseType;
        uint64 period;
        uint64 expiry;
        address oracle;
        address underlying;
        address strike;
        uint256 frequency;
    }

    /*///////////////////////////////////////////////////////////////
                       State Variables V1
    //////////////////////////////////////////////////////////////*/

    /// @dev instrumentId => instrument
    mapping(uint256 => Instrument) public instruments;

    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event InstrumentComponentSettled(address account, bool isCoupon, uint8 index, uint256 payout);
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

        instruments[id].period = sInstrument.period;
        instruments[id].engineId = sInstrument.engineId;
        instruments[id].autocallId = sInstrument.autocallId;
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
     * @param _instrumentId instrument id`
     */
    function getDetailFromInstrumentId(uint256 _instrumentId)
        public
        view
        returns (uint64 period, uint8 engine, uint40 autocallId, uint256 coupons, Option[] memory options)
    {
        Instrument memory _instrument = instruments[_instrumentId];
        period = _instrument.period;
        engine = _instrument.engineId;
        autocallId = _instrument.autocallId;
        coupons = _instrument.coupons;
        options = _instrument.options;
    }

    function getInitialSpotPrice(uint256 _instrumentId) public view returns (uint256 price) {
        (uint64 period,,,, Option[] memory options) = getDetailFromInstrumentId(_instrumentId);
        (, uint40 productId, uint64 expiry,,) = TokenIdUtil.parseTokenId(options[0].tokenId);
        (address oracle,, address underlying,, address strike,,,) = getDetailFromProductId(productId);
        return _getOraclePrice(oracle, underlying, strike, expiry - period);
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
     * @return breaches Array of breach structs representing potential barrier breaches
     * @return breachCount Total number of breaches from all the barrier updates
     */
    function getBarrierBreaches(uint256 _instrumentId, uint32 _barrierId)
        public
        view
        returns (Breach[] memory breaches, uint32 breachCount)
    {
        BreachDetail memory details = _parseBreachDetail(_instrumentId, _barrierId);
        uint256[] memory updates = IInstrumentOracle(details.oracle).barrierUpdates(_instrumentId, _barrierId);
        _handleBarrierChecks(updates, details.exerciseType, details.expiry, details.expiry - details.period, details.frequency);
        return _getBarrierBreaches(
            details.oracle, details.underlying, details.strike, details.barrierPCT, details.expiry, details.period, updates
        );
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
        // Settle Instrument

        uint8 instrumentEngineId = instruments[_instrumentId].engineId;
        uint40 autocallId = instruments[_instrumentId].autocallId;
        uint256 coupons = instruments[_instrumentId].coupons;
        Option[] memory options = instruments[_instrumentId].options;

        payouts = getInstrumentPayout(instrumentEngineId, autocallId, coupons, options, _amount);

        for (uint8 i; i < payouts.length;) {
            InstrumentComponentBalance memory payout = payouts[i];
            emit InstrumentComponentSettled(_account, payout.isCoupon, payout.index, payout.amount);

            if (!payout.isCoupon) {
                optionToken.burnGrappaOnly(engines[instrumentEngineId], options[payout.index].tokenId, _amount);
            }

            IMarginEngine(engines[payout.engineId]).payCashValue(assets[payout.collateralId].addr, _account, payout.amount);
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
     * @param _option  option
     * @param _amount amount to settle
     *
     * @return payout amount paid
     *
     */
    function getOptionPayout(Option memory _option, uint256 _amount) public view returns (uint256 payout) {
        uint256 payoutPerOption;
        (payoutPerOption) = _getPayoutPerOption(_option);
        payout = payoutPerOption * _amount;
        unchecked {
            payout = payout / UNIT;
        }
    }

    /**
     * @dev calculate the payout for one coupon
     *
     * @param _coupons  coupons
     * @param _index index
     * @param _amount amount to settle
     *
     * @return payout amount paid
     *
     */
    function getCouponPayout(uint256 _coupons, uint256 _index, uint256 _amount) public view returns (uint256 payout) {
        uint256 payoutPerCoupon;
        (payoutPerCoupon) = _getPayoutPerCoupon(_coupons, _index);
        payout = payoutPerCoupon * _amount;
        unchecked {
            payout = payout / UNIT;
        }
    }

    /**
     * @dev calculate the payout for instruments
     *
     * @param _instrumentEngineId  instrument engine id
     * @param _autocallId  autocall id
     * @param _coupons  coupons
     * @param _options  options
     * @param _amount   amount to settle
     * @return payouts amounts paid
     *
     */
    function getInstrumentPayout(
        uint8 _instrumentEngineId,
        uint40 _autocallId,
        uint256 _coupons,
        Option[] memory _options,
        uint256 _amount
    ) public view returns (InstrumentComponentBalance[] memory payouts) {
        // Add payouts of all the coupons
        for (uint8 i; i < MAX_COUPON_CONSTRUCTION;) {
            uint256 payout = getCouponPayout(_coupons, i, _amount);
            payouts = _addToPayouts(payouts, true, i, _instrumentEngineId, TokenIdUtil.parseStrikeId(_options[0].tokenId), payout);
            unchecked {
                ++i;
            }
        }

        // Add payouts of all the options
        for (uint8 i; i < _options.length;) {
            Option memory option = _options[i];
            uint256 payout = getOptionPayout(option, _amount);
            payouts = _addToPayouts(
                payouts,
                false,
                i,
                TokenIdUtil.parseEngineId(option.tokenId),
                TokenIdUtil.parseCollateralId(option.tokenId),
                payout
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev calculate the payout for one coupon unit
     *
     * @param _coupons  coupons
     * @param _index  index within coupons
     *
     * @return payoutPerCoupon amount paid
     *
     */
    function _getPayoutPerCoupon(uint256 _coupons, uint256 _index) internal pure returns (uint256) {
        (uint16 couponPCT, uint16 numInstallements, CouponType couponType, uint32 barrierId) =
            getDetailFromCouponId(_coupons, _index);

        (
            uint16 barrierPCT,
            BarrierObservationFrequencyType observationFrequency,
            BarrierTriggerType triggerType,
            BarrierExerciseType exerciseType
        ) = getDetailFromBarrierId(barrierId);

        //TODO

        return 0;
    }

    /**
     * @dev calculate the payout for one option token
     *
     * @param _option  option struct
     *
     * @return payoutPerOption amount paid
     *
     */
    function _getPayoutPerOption(Option memory _option) internal view returns (uint256) {
        if (!TokenIdUtil.isExpired(_option.tokenId)) {
            return 0;
        }

        (,, uint256 payoutPerOption) = _getPayoutPerToken(_option.tokenId);
        //TODO (add participation, barrier pct update)
        return payoutPerOption;
    }

    /**
     * @dev add an entry to array of InstrumentComponentBalance
     * @param _payouts existing payout array
     * @param _isCoupon whether it is coupon (true) or option (false)
     * @param _index index in coupons or options array
     * @param _engineId engine id
     * @param _collateralId collateral id
     * @param _payout new payout
     */
    function _addToPayouts(
        InstrumentComponentBalance[] memory _payouts,
        bool _isCoupon,
        uint8 _index,
        uint8 _engineId,
        uint8 _collateralId,
        uint256 _payout
    ) internal pure returns (InstrumentComponentBalance[] memory) {
        if (_payout == 0) return _payouts;

        _payouts.append(InstrumentComponentBalance(_isCoupon, _index, _engineId, _collateralId, _payout.toUint80()));

        return _payouts;
    }

    function _parseBreachDetail(uint256 _instrumentId, uint32 _barrierId) internal view returns (BreachDetail memory details) {
        (uint16 _barrierPCT, BarrierObservationFrequencyType _observationFrequency,, BarrierExerciseType _exerciseType) =
            getDetailFromBarrierId(_barrierId);
        (uint64 _period,,,, Option[] memory _options) = getDetailFromInstrumentId(_instrumentId);
        (, uint40 _productId, uint64 _expiry,,) = TokenIdUtil.parseTokenId(_options[0].tokenId);
        (address _oracle,, address _underlying,, address _strike,,,) = getDetailFromProductId(_productId);
        uint256 _frequency = convertBarrierObservationFrequencyType(_observationFrequency);
        return BreachDetail({
            barrierPCT: _barrierPCT,
            exerciseType: _exerciseType,
            period: _period,
            expiry: _expiry,
            oracle: _oracle,
            underlying: _underlying,
            strike: _strike,
            frequency: _frequency
        });
    }

    function _handleBarrierChecks(
        uint256[] memory _updates,
        BarrierExerciseType _exerciseType,
        uint64 _expiry,
        uint256 _creationTimestamp,
        uint256 _frequency
    ) internal pure {
        if (_exerciseType == BarrierExerciseType.EUROPEAN) {
            // Exactly one update at expiry
            if (_updates.length != 1 || _updates[0] != _expiry) {
                revert GP_MissingBarrierUpdate();
            }
        } else if (_exerciseType == BarrierExerciseType.CONTINUOUS) {
            // At least one update at or before expiry
            if (_updates.length < 1) {
                revert GP_MissingBarrierUpdate();
            }
            uint256 lastTimestamp = _updates[_updates.length - 1];
            if (lastTimestamp > _expiry) {
                revert GP_MissingBarrierUpdate();
            }
        } else if (_exerciseType == BarrierExerciseType.DISCRETE) {
            for (uint256 i = 0; i < _updates.length; i++) {
                if (_updates[i] != _creationTimestamp + (i + 1) * _frequency) {
                    revert GP_InvalidBarrierUpdate();
                }
            }
        } else {
            revert GP_InvalidBarrierExerciseType();
        }
    }

    /**
     * Helper function to calculate number of breaches and populate an array of breach timestamps to be returned
     * @param _oracle oracle adress to check
     * @param _underlying underlying address for the barrier
     * @param _strike strike asset for the barrier (usually USD/C)
     * @param _barrierPCT barrier percentage in {UNIT_PERCENTAGE_DECIMALS}
     * @param _expiry expiry timestamp of the instrument
     * @param _period duration of the instrument
     * @param _updates array of timestamps of all barrier updates (could be breaches or observations)
     */
    function _getBarrierBreaches(
        address _oracle,
        address _underlying,
        address _strike,
        uint16 _barrierPCT,
        uint256 _expiry,
        uint64 _period,
        uint256[] memory _updates
    ) internal view returns (Breach[] memory breaches, uint32 breachCount) {
        uint256 spotPriceAtCreation = _getOraclePrice(_oracle, _underlying, _strike, _expiry - _period);
        // By rounding up below, we end up favouring certain barriers over others
        uint256 barrierBreachThreshold = spotPriceAtCreation.mulDivUp(_barrierPCT, UNIT_PERCENTAGE);
        Breach[] memory _breaches = new Breach[](_updates.length);
        uint32 _breachCount = 0;
        for (uint256 i = 0; i < _updates.length; i++) {
            uint256 updatePrice = _getOraclePrice(_oracle, _underlying, _strike, _updates[i]);
            Breach memory currBreach = Breach({timestamp: _updates[i], isBreached: false});
            // A valid breach is (1) at or before expiry, (2) breaches the barrier amount
            if (_updates[i] <= _expiry && _comparePricesForBarrierBreach(barrierBreachThreshold, updatePrice, _barrierPCT)) {
                currBreach.isBreached = true;
                _breachCount++;
            }
            _breaches[i] = currBreach;
        }
        return (_breaches, _breachCount);
    }

    function _comparePricesForBarrierBreach(uint256 _barrierBreachThreshold, uint256 _comparisonPrice, uint16 _barrierPCT)
        internal
        pure
        returns (bool isBreached)
    {
        if (_barrierPCT < UNIT_PERCENTAGE) {
            return _comparisonPrice < _barrierBreachThreshold;
        } else {
            return _comparisonPrice > _barrierBreachThreshold;
        }
    }
}
