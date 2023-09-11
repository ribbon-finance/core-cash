// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import test base and helpers.
import "forge-std/Test.sol";

import {Grappa} from "../../src/core/Grappa.sol";
import {InstrumentGrappa} from "../../src/core/InstrumentGrappa.sol";
import {TokenIdUtil} from "../../src/libraries/TokenIdUtil.sol";
import {InstrumentIdUtil} from "../../src/libraries/InstrumentIdUtil.sol";
import {PythInstrumentOracleDisputable} from "../../src/core/oracles/PythInstrumentOracleDisputable.sol";

import "../../src/config/enums.sol";
import "../../src/config/types.sol";
import "../../src/config/constants.sol";
import "../../src/config/errors.sol";

contract InstrumentGrappaHarness is InstrumentGrappa {
    constructor(address _optionToken, address _instrumentToken) InstrumentGrappa(_optionToken, _instrumentToken) {}

    function exposedGetBarrierBreaches(uint256 _instrumentId, uint32 _barrierId, InstrumentIdUtil.BreachDetail memory _details)
        public
        view
        returns (uint256[] memory breaches)
    {
        return _getBarrierBreaches(_instrumentId, _barrierId, _details);
    }
}

contract InstrumentGrappaTest is Test {
    InstrumentGrappaHarness private instrumentGrappaHarness;
    PythInstrumentOracleDisputable private oracle;
    uint64 public immutable initialTimestamp = 100;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant PYTH = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97; // Dummy
    address[] public COMBINED_ADDRESSES = [PYTH]; // Dummy

    bytes32 public constant USDC_PRICE_FEED = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a; // Dummy
    bytes32[] public COMBINED_PRICE_FEEDS = [USDC_PRICE_FEED]; // Dummy

    function setUp() public {
        instrumentGrappaHarness = new InstrumentGrappaHarness(address(1), address(2));
        oracle = new PythInstrumentOracleDisputable(address(this), PYTH, COMBINED_PRICE_FEEDS, COMBINED_ADDRESSES);
        vm.warp(initialTimestamp);
    }

    // TODO write integration tests for false positive and false negative recovery flows
    // #_getBarrierBreaches

    // EUROPEAN

    function testGetBarrierBreachEuropeanPastBarrier() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(90 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.EUROPEAN,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 90 * UNIT
        });
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 500),
            abi.encode(80 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 500);
    }

    function testGetBarrierBreachEuropeanNotPastBarrier() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(110 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.EUROPEAN,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 110 * UNIT
        });
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 500),
            abi.encode(80 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    function testGetBarrierBreachEuropeanAtBarrier() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(110 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.EUROPEAN,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 110 * UNIT
        });
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 500),
            abi.encode(110 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    function testGetBarrierBreachEuropeanWithoutExpiryPriceReverts() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(110 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.EUROPEAN,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 110 * UNIT
        });
        vm.expectRevert(OC_PriceNotReported.selector);
        instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
    }

    // CONTINUOUS

    function testGetBarrierBreachContinuousNoBreach() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(110 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.CONTINUOUS,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 110 * UNIT
        });
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.barrierBreaches.selector, 1, 1), abi.encode(0));
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    function testGetBarrierBreachContinuousBreach() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(110 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.CONTINUOUS,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 110 * UNIT
        });
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.barrierBreaches.selector, 1, 1), abi.encode(150));
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 150),
            abi.encode(111 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 150);
    }

    function testGetBarrierBreachContinuousBreachAfterExpiryIgnored() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(110 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.CONTINUOUS,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 110 * UNIT
        });
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.barrierBreaches.selector, 1, 1), abi.encode(550));
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 550),
            abi.encode(111 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    function testGetBarrierBreachContinuousUnderlyingPriceNotBreachedIgnored() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(90 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.CONTINUOUS,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 1,
            breachThreshold: 90 * UNIT
        });
        vm.mockCall(address(oracle), abi.encodeWithSelector(oracle.barrierBreaches.selector, 1, 1), abi.encode(150));
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 150),
            abi.encode(90 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    // DISCRETE

    function testGetBarrierBreachDiscreteNoBreach() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(90 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.DISCRETE,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 300,
            breachThreshold: 90 * UNIT
        });
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 400), // First update is (500 - 400 + 300 = 400)
            abi.encode(90 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 1);
        assertEq(result[0], 0);
    }

    function testGetBarrierBreachDiscreteMultipleBreaches() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(90 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.DISCRETE,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 100,
            breachThreshold: 90 * UNIT
        });
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 200), // First update is (500 - 400 + 100 = 200)
            abi.encode(89 * UNIT, true)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 300),
            abi.encode(90 * UNIT, true)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 400),
            abi.encode(91 * UNIT, true)
        );
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 500),
            abi.encode(88 * UNIT, true)
        );
        uint256[] memory result = instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
        assertEq(result.length, 4);
        assertEq(result[0], 200);
        assertEq(result[1], 0);
        assertEq(result[2], 0);
        assertEq(result[3], 500);
    }

    function testGetBarrierBreachDiscreteWithoutExpiryPriceReverts() public {
        InstrumentIdUtil.BreachDetail memory mockDetails = InstrumentIdUtil.BreachDetail({
            barrierPCT: uint16(90 * 10 ** UNIT_PERCENTAGE_DECIMALS),
            exerciseType: BarrierExerciseType.DISCRETE,
            period: 400,
            expiry: 500,
            oracle: address(oracle),
            underlying: WETH,
            strike: USDC,
            frequency: 200,
            breachThreshold: 90 * UNIT
        });
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceAtTimestamp.selector, WETH, USDC, 200), // First update is (500 - 400 + 200 = 300)
            abi.encode(89 * UNIT, true)
        );
        // Missing the update at 500
        vm.expectRevert(OC_PriceNotReported.selector);
        instrumentGrappaHarness.exposedGetBarrierBreaches(1, 1, mockDetails);
    }
}
