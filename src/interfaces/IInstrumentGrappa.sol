// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGrappa} from "./IGrappa.sol";
import "../config/types.sol";
import "../config/enums.sol";

interface IInstrumentGrappa is IGrappa {
    function instrumentToken() external view returns (address);
    function registerInstrument() external returns (uint256);
    function serialize(InstrumentExtended calldata) external returns (Instrument memory);
    function getDetailFromInstrumentId(uint256) external view returns (uint8, uint8, uint32, uint64, uint256, Option[] memory);
    function getInitialSpotPrice(uint256) external view returns (uint256);
    function getDetailFromCouponId(uint64) external pure returns (uint16, bool, CouponType, uint32);
    function getDetailFromCouponId(uint256, uint256) external pure returns (uint16, bool, CouponType, uint32);
    function getDetailFromBarrierId(uint32) external pure returns (uint16, BarrierObservationFrequencyType, BarrierTriggerType);
    function getExpiry(uint256) external view returns (uint64);
    function getFrequency(BarrierObservationFrequencyType) external view returns (uint256);
    function getInstrumentId(Instrument calldata) external view returns (uint256);
    function getInstrumentId(InstrumentExtended calldata) external view returns (uint256);
    function getCouponId(uint16, bool, CouponType, uint32) external pure returns (uint64);
    function getCoupons(uint64[] calldata) external pure returns (uint256);
    function getBarrierId(uint16, BarrierObservationFrequencyType, BarrierTriggerType) external pure returns (uint32);

    function getBarrierBreaches(uint256, uint32) external view returns (uint256[] memory);
    function settleInstrument(address, uint256, uint256) external returns (InstrumentComponentBalance[] memory);

    function getOptionPayout(uint256, Option memory, uint256) external returns (uint256);
    function getCouponPayout(uint256, uint256, uint256, uint256) external returns (uint256);
    function getInstrumentPayout(uint256, uint256) external view returns (InstrumentComponentBalance[] memory);
}
