// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import test base and helpers.
import "forge-std/Test.sol";
import {OracleHelper} from "./OracleHelper.sol";

import {PythOracle} from "../../../src/core/oracles/PythOracle.sol";

import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

import "../../../src/config/constants.sol";
import "../../../src/core/oracles/errors.sol";

contract PythOracleHarness is PythOracle {
    constructor(address _owner, address _pyth, bytes32[] memory _initialFeedIds, address[] memory _initialBaseAddresses)
        PythOracle(_owner, _pyth, _initialFeedIds, _initialBaseAddresses)
    {}

    function exposedToPriceWithUnitDecimalsBaseOracle(uint256 _basePrice, uint8 _baseDecimals) public pure returns (uint256) {
        return _toPriceWithUnitDecimals(_basePrice, _baseDecimals);
    }

    function exposedToPriceWithUnitDecimalsPyth(PythStructs.Price memory _price) public pure returns (uint256 price) {
        return _toPriceWithUnitDecimals(_price);
    }
}

contract PythOracleTest is OracleHelper {
    PythOracle private oracle;
    PythOracleHarness private harnessOracle;
    uint64 public immutable initialTimestamp = 100;
    uint64 private constant expiryToTest = 50;
    uint256 private constant priceToTest = 3000 * UNIT;

    function setUp() public {
        oracle = new PythOracle(address(this), PYTH, COMBINED_PRICE_FEEDS, COMBINED_ADDRESSES);
        harnessOracle = new PythOracleHarness(address(this), PYTH, COMBINED_PRICE_FEEDS, COMBINED_ADDRESSES);
        vm.warp(initialTimestamp);
    }

    // # constructor

    function testConstructor() public {
        // Check correct owner
        assertEq(oracle.owner(), address(this));
        // Check pyth values
        assertEq(address(oracle.pyth()), PYTH);
        assertEq(oracle.priceFeedIds(USDC_PRICE_FEED), USDC);
        assertEq(oracle.priceFeedIds(WETH_PRICE_FEED), WETH);
        assertEq(oracle.priceFeedIds(WBTC_PRICE_FEED), WBTC);
    }

    // BaseOracle Tests

    // #isPriceFinalized

    function testIsPriceFinalized() public {
        // Since non-disputable oracle, all prices (even unreported ones) are always finalized.
        // I.e. should revert earlier in getPriceAtTimestamp() if unreported
        bool isFinalized = oracle.isPriceFinalized(WETH, expiryToTest);
        assertEq(isFinalized, true);
    }

    // #setPriceBackup

    function testSetPriceBackup() public {
        oracle.setGracePeriod(100);
        assertEq(oracle.gracePeriod(), 100);
        vm.warp(expiryToTest + oracle.gracePeriod());
        setPriceBackupWithChecks(WETH, expiryToTest, 3500 * UNIT, oracle);
    }

    function testSetPriceBackupWhenPriceAlreadySetReverts() public {
        bytes[] memory dummyPythUpdateData = new bytes[](1);
        dummyPythUpdateData[0] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        dummyPriceFeedIds[0] = WETH_PRICE_FEED;
        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory pricesToTest = new uint256[](1);
        pricesToTest[0] = priceToTest;
        PythStructs.PriceFeed[] memory resultPriceFeeds = new PythStructs.PriceFeed[](1);
        PythStructs.PriceFeed memory wethResult =
            getPythPriceFeedStruct(3000 * 10 ** 8, RANDOM_PYTH_CONF, -8, expiryToTest, WETH_PRICE_FEED);
        resultPriceFeeds[0] = wethResult;
        reportPriceWithChecks(
            dummyPythUpdateData, dummyPriceFeedIds, expiryToTest, pricesToTest, resultPriceFeeds, assets, oracle
        );
        vm.expectRevert(OC_PriceReported.selector);
        oracle.setPriceBackup(WETH, expiryToTest, 3500 * UNIT);
    }

    function testSetPriceBackupBeforeGracePeriodOverReverts() public {
        oracle.setGracePeriod(100);
        assertEq(oracle.gracePeriod(), 100);
        vm.warp(expiryToTest + (oracle.gracePeriod() - 1));
        vm.expectRevert(OC_GracePeriodNotOver.selector);
        oracle.setPriceBackup(WETH, expiryToTest, 3500 * UNIT);
    }

    function testSetPriceBackupTwiceReverts() public {
        vm.warp(expiryToTest + oracle.gracePeriod());
        setPriceBackupWithChecks(WETH, expiryToTest, 3500 * UNIT, oracle);

        vm.expectRevert(OC_PriceReported.selector);
        oracle.setPriceBackup(WETH, expiryToTest, 4000 * UNIT);
    }

    // #setStableAsset

    function testSetStableAssetWithOwner() public {
        setStableAssetWithChecks(WETH, true, oracle);
    }

    function testSetStableAssetWithoutOwnerReverts() public {
        vm.prank(NON_OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setStableAsset(WETH, true);
    }

    function testSetStableAssetZeroAddressReverts() public {
        vm.expectRevert(OC_ZeroAddress.selector);
        oracle.setStableAsset(address(0), true);
    }

    // #setGracePeriod

    function testSetGracePeriodWithOwner() public {
        oracle.setGracePeriod(100);
        assertEq(oracle.gracePeriod(), 100);
    }

    function testSetGracePeriodWithoutOwnerReverts() public {
        vm.prank(NON_OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setGracePeriod(100);
    }

    function testSetGracePeriodZeroPeriodReverts() public {
        vm.expectRevert(OC_InvalidPeriod.selector);
        oracle.setGracePeriod(0);
    }

    // #_getPriceAtTimestamp

    function testGetPriceAtTimestampStableAsset() public {
        setStableAssetWithChecks(USDC, true, oracle);
        (uint256 price, bool isFinalized) = oracle.getPriceAtTimestamp(USDC, USDC, expiryToTest);
        assertEq(price, UNIT);
        assertEq(isFinalized, true);
    }

    function testGetPriceAtTimestampNormalAsset() public {
        defaultReportPrice(priceToTest, expiryToTest, oracle);
        (uint256 price, bool isFinalized) = oracle.getPriceAtTimestamp(WETH, USDC, expiryToTest);
        assertEq(price, priceToTest);
        assertEq(isFinalized, true);
    }

    function testGetPriceAtTimestampUnreportedPriceReverts() public {
        vm.expectRevert(OC_PriceNotReported.selector);
        oracle.getPriceAtTimestamp(WETH, USDC, expiryToTest);
    }

    // #_toPriceWithUnitDecimals (BaseOracle)

    function testToPriceWithUnitDecimalsBaseOracle() public {
        // decimals = UNIT_DECIMALS
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(10, UNIT_DECIMALS), 10);
        // decimals > UNIT_DECIMALS (some precison lost)
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(12345678, UNIT_DECIMALS + 2), 123456);
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(87654321, UNIT_DECIMALS + 2), 876543);
        // decimals < UNIT_DECIMALS
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(10, 0), 10 * 10 ** UNIT_DECIMALS);
        // all precision lost
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(1, UNIT_DECIMALS + 1), 0);
        // zero cases
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(0, 0), 0);
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(0, UNIT_DECIMALS + 1), 0);
        assertEq(harnessOracle.exposedToPriceWithUnitDecimalsBaseOracle(0, UNIT_DECIMALS - 1), 0);
    }

    // PythOracle Tests

    // #disputePeriod

    function testDisputePeriodIsZero() public {
        uint256 period = oracle.maxDisputePeriod();
        assertEq(period, 0);
    }

    // #reportPrice

    function testReportPriceSingle() public {
        defaultReportPrice(priceToTest, expiryToTest, oracle);
    }

    function testReportPriceMultiple() public {
        bytes[] memory dummyPythUpdateData = new bytes[](3);
        // We use 3 to represent USDC, WETH and WBTC
        for (uint8 i = 0; i < 3; i++) {
            dummyPythUpdateData[i] = bytes("0");
        }
        PythStructs.PriceFeed[] memory resultPriceFeeds = new PythStructs.PriceFeed[](3);
        uint256[] memory pricesToTest = new uint256[](3);
        pricesToTest[0] = 1 * UNIT;
        pricesToTest[1] = priceToTest;
        pricesToTest[2] = 25000 * UNIT;
        PythStructs.PriceFeed memory usdcResult =
            getPythPriceFeedStruct(1 * 10 ** 6, RANDOM_PYTH_CONF, -6, expiryToTest, USDC_PRICE_FEED);
        PythStructs.PriceFeed memory wethResult =
            getPythPriceFeedStruct(3000 * 10 ** 8, RANDOM_PYTH_CONF, -8, expiryToTest, WETH_PRICE_FEED);
        PythStructs.PriceFeed memory wbtcResult =
            getPythPriceFeedStruct(25000 * 10 ** 4, RANDOM_PYTH_CONF, -4, expiryToTest, WBTC_PRICE_FEED);
        resultPriceFeeds[0] = usdcResult;
        resultPriceFeeds[1] = wethResult;
        resultPriceFeeds[2] = wbtcResult;
        reportPriceWithChecks(
            dummyPythUpdateData, COMBINED_PRICE_FEEDS, expiryToTest, pricesToTest, resultPriceFeeds, COMBINED_ADDRESSES, oracle
        );
    }

    function testReportPriceForFutureReverts() public {
        bytes[] memory dummyPythUpdateData = new bytes[](1);
        dummyPythUpdateData[0] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        dummyPriceFeedIds[0] = WETH_PRICE_FEED;
        vm.expectRevert(OC_CannotReportForFuture.selector);
        oracle.reportPrice(dummyPythUpdateData, dummyPriceFeedIds, uint64(block.timestamp + 1));
    }

    function testReportPriceWithDifferentArgumentLengthsReverts() public {
        bytes[] memory dummyPythUpdateData = new bytes[](2);
        dummyPythUpdateData[0] = bytes("0");
        dummyPythUpdateData[1] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        dummyPriceFeedIds[0] = WETH_PRICE_FEED;
        vm.expectRevert(OC_ArgumentsLengthError.selector);
        oracle.reportPrice(dummyPythUpdateData, dummyPriceFeedIds, expiryToTest);
    }

    function testReportPriceWithoutPriceFeedReverts() public {
        bytes[] memory dummyPythUpdateData = new bytes[](1);
        dummyPythUpdateData[0] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        bytes32 randomPriceFeed = keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender));
        dummyPriceFeedIds[0] = randomPriceFeed;
        address[] memory assets = new address[](1);
        assets[0] = address(1); // Random asset
        uint256[] memory pricesToTest = new uint256[](1);
        pricesToTest[0] = priceToTest;
        PythStructs.PriceFeed[] memory resultPriceFeeds = new PythStructs.PriceFeed[](1);
        PythStructs.PriceFeed memory randomAssetResult =
            getPythPriceFeedStruct(3000 * 10 ** 8, RANDOM_PYTH_CONF, -8, expiryToTest, randomPriceFeed);
        resultPriceFeeds[0] = randomAssetResult;
        vm.expectRevert(PY_AssetPriceFeedNotSet.selector);
        reportPriceHelper(dummyPythUpdateData, dummyPriceFeedIds, expiryToTest, resultPriceFeeds, oracle);
    }

    function testReportPriceDifferentPublishProvidedTimestampsReverts() public {
        bytes[] memory dummyPythUpdateData = new bytes[](1);
        dummyPythUpdateData[0] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        dummyPriceFeedIds[0] = WETH_PRICE_FEED;
        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory pricesToTest = new uint256[](1);
        pricesToTest[0] = priceToTest;
        PythStructs.PriceFeed[] memory resultPriceFeeds = new PythStructs.PriceFeed[](1);
        PythStructs.PriceFeed memory wethResult =
            getPythPriceFeedStruct(3000 * 10 ** 8, RANDOM_PYTH_CONF, -8, expiryToTest + 1, WETH_PRICE_FEED);
        resultPriceFeeds[0] = wethResult;
        vm.mockCall(PYTH, abi.encodeWithSelector(IPyth.getUpdateFee.selector), abi.encode(1 wei));
        vm.mockCall(
            PYTH,
            1,
            abi.encodeWithSelector(
                IPyth.parsePriceFeedUpdates.selector, dummyPythUpdateData, dummyPriceFeedIds, expiryToTest, expiryToTest
            ),
            abi.encode(resultPriceFeeds)
        );
        vm.expectRevert(PY_DifferentPublishProvidedTimestamps.selector);
        oracle.reportPrice(dummyPythUpdateData, dummyPriceFeedIds, expiryToTest);
    }

    function testReportPriceForReportedExpiryReverts() public {
        bytes[] memory dummyPythUpdateData = new bytes[](1);
        dummyPythUpdateData[0] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        dummyPriceFeedIds[0] = WETH_PRICE_FEED;
        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory pricesToTest = new uint256[](1);
        pricesToTest[0] = priceToTest;
        PythStructs.PriceFeed[] memory resultPriceFeeds = new PythStructs.PriceFeed[](1);
        PythStructs.PriceFeed memory wethResult =
            getPythPriceFeedStruct(3000 * 10 ** 8, RANDOM_PYTH_CONF, -8, expiryToTest, WETH_PRICE_FEED);
        resultPriceFeeds[0] = wethResult;
        reportPriceWithChecks(
            dummyPythUpdateData, dummyPriceFeedIds, expiryToTest, pricesToTest, resultPriceFeeds, assets, oracle
        );
        vm.expectRevert(OC_PriceReported.selector);
        reportPriceHelper(dummyPythUpdateData, dummyPriceFeedIds, expiryToTest, resultPriceFeeds, oracle);
    }

    // #setPriceFeedID

    function testSetPriceFeedIDWithOwner() public {
        oracle.setPriceFeedID(WETH, WETH_PRICE_FEED);
        assertEq(oracle.priceFeedIds(WETH_PRICE_FEED), WETH);
    }

    function testPriceFeedIDWithoutOwnerReverts() public {
        vm.prank(NON_OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        oracle.setPriceFeedID(WETH, WETH_PRICE_FEED);
    }

    function testSetPriceFeedIDZeroIDReverts() public {
        vm.expectRevert(PY_InvalidPriceFeedID.selector);
        oracle.setPriceFeedID(WETH, bytes32(0));
    }

    function testSetPriceFeedIDZeroAddressReverts() public {
        vm.expectRevert(OC_ZeroAddress.selector);
        oracle.setPriceFeedID(address(0), WETH_PRICE_FEED);
    }

    // #_toPriceWithUnitDecimals (Pyth)

    function testToPriceWithUnitDecimalsPythGreaterThanUnitDecimals() public {
        PythStructs.PriceFeed memory testPriceFeedOne =
            getPythPriceFeedStruct(300087654321, RANDOM_PYTH_CONF, -8, expiryToTest, WETH_PRICE_FEED);
        uint256 resultOne = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedOne.price);
        assertEq(resultOne, 3000876543);
        PythStructs.PriceFeed memory testPriceFeedTwo =
            getPythPriceFeedStruct(30009999999999, RANDOM_PYTH_CONF, -10, expiryToTest, WETH_PRICE_FEED);
        uint256 resultTwo = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedTwo.price);
        assertEq(resultTwo, 3000999999);
        PythStructs.PriceFeed memory testPriceFeedThree =
            getPythPriceFeedStruct(1, RANDOM_PYTH_CONF, -12, expiryToTest, WETH_PRICE_FEED);
        uint256 resultThree = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedThree.price);
        assertEq(resultThree, 0);
    }

    function testToPriceWithUnitDecimalsPythLesserThanUnitDecimals() public {
        PythStructs.PriceFeed memory testPriceFeedOne =
            getPythPriceFeedStruct(30001, RANDOM_PYTH_CONF, -1, expiryToTest, WETH_PRICE_FEED);
        uint256 resultOne = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedOne.price);
        assertEq(resultOne, 3000100000);
        PythStructs.PriceFeed memory testPriceFeedTwo =
            getPythPriceFeedStruct(3000999, RANDOM_PYTH_CONF, -3, expiryToTest, WETH_PRICE_FEED);
        uint256 resultTwo = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedTwo.price);
        assertEq(resultTwo, 3000999000);
        PythStructs.PriceFeed memory testPriceFeedThree =
            getPythPriceFeedStruct(1, RANDOM_PYTH_CONF, -5, expiryToTest, WETH_PRICE_FEED);
        uint256 resultThree = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedThree.price);
        assertEq(resultThree, 10);
    }

    function testToPriceWithUnitDecimalsPythSpecialCases() public {
        PythStructs.PriceFeed memory testPriceFeedOne =
            getPythPriceFeedStruct(3000123456, RANDOM_PYTH_CONF, -6, expiryToTest, WETH_PRICE_FEED);
        uint256 resultOne = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedOne.price);
        assertEq(resultOne, 3000123456);
        PythStructs.PriceFeed memory testPriceFeedTwo =
            getPythPriceFeedStruct(0, RANDOM_PYTH_CONF, -6, expiryToTest, WETH_PRICE_FEED);
        uint256 resultTwo = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedTwo.price);
        assertEq(resultTwo, 0);
        PythStructs.PriceFeed memory testPriceFeedThree =
            getPythPriceFeedStruct(0, RANDOM_PYTH_CONF, -8, expiryToTest, WETH_PRICE_FEED);
        uint256 resultThree = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedThree.price);
        assertEq(resultThree, 0);
        PythStructs.PriceFeed memory testPriceFeedFour =
            getPythPriceFeedStruct(0, RANDOM_PYTH_CONF, -4, expiryToTest, WETH_PRICE_FEED);
        uint256 resultFour = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedFour.price);
        assertEq(resultFour, 0);
        PythStructs.PriceFeed memory testPriceFeedFive =
            getPythPriceFeedStruct(3000, RANDOM_PYTH_CONF, 0, expiryToTest, WETH_PRICE_FEED);
        uint256 resultFive = harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedFive.price);
        assertEq(resultFive, 3000000000);
    }

    function testToPriceWithUnitDecimalsPyttRevertCases() public {
        // Positive exponent
        PythStructs.PriceFeed memory testPriceFeedOne =
            getPythPriceFeedStruct(3000123456, RANDOM_PYTH_CONF, 1, expiryToTest, WETH_PRICE_FEED);
        vm.expectRevert(PY_PythPriceConversionError.selector);
        harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedOne.price);

        // Negative price
        PythStructs.PriceFeed memory testPriceFeedTwo =
            getPythPriceFeedStruct(-30000, RANDOM_PYTH_CONF, -1, expiryToTest, WETH_PRICE_FEED);
        vm.expectRevert(PY_PythPriceConversionError.selector);
        harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedTwo.price);

        // Exponent too large
        PythStructs.PriceFeed memory testPriceFeedThree =
            getPythPriceFeedStruct(3000123456, RANDOM_PYTH_CONF, -256, expiryToTest, WETH_PRICE_FEED);
        vm.expectRevert(PY_PythPriceConversionError.selector);
        harnessOracle.exposedToPriceWithUnitDecimalsPyth(testPriceFeedThree.price);
    }
}
