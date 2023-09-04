// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import test base and helpers.
import "forge-std/Test.sol";

import {BaseOracle} from "../../../src/core/oracles/abstract/BaseOracle.sol";
import {DisputableOracle} from "../../../src/core/oracles/abstract/DisputableOracle.sol";
import {PythOracle} from "../../../src/core/oracles/PythOracle.sol";

import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

abstract contract OracleHelper is Test {
    // Addresses
    address public constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address public constant NON_OWNER = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;

    address[] public COMBINED_ADDRESSES = [USDC, WETH, WBTC];

    // Price Feed IDs
    bytes32 public constant USDC_PRICE_FEED = 0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a;
    bytes32 public constant WETH_PRICE_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant WBTC_PRICE_FEED = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    bytes32[] public COMBINED_PRICE_FEEDS = [USDC_PRICE_FEED, WETH_PRICE_FEED, WBTC_PRICE_FEED];

    uint64 public constant RANDOM_PYTH_CONF = 35753;

    function getPythPriceStruct(int64 _price, uint64 _conf, int32 _expo, uint256 _publishTime)
        public
        pure
        returns (PythStructs.Price memory)
    {
        PythStructs.Price memory priceStruct =
            PythStructs.Price({price: _price, conf: _conf, expo: _expo, publishTime: _publishTime});

        return priceStruct;
    }

    function getPythPriceFeedStruct(int64 _price, uint64 _conf, int32 _expo, uint256 _publishTime, bytes32 _id)
        public
        pure
        returns (PythStructs.PriceFeed memory)
    {
        PythStructs.Price memory priceStruct = getPythPriceStruct(_price, _conf, _expo, _publishTime);

        // We just assume the EMA price is the same as the actual price
        PythStructs.Price memory emaPriceStruct = getPythPriceStruct(_price, _conf, _expo, _publishTime);

        return PythStructs.PriceFeed({id: _id, price: priceStruct, emaPrice: emaPriceStruct});
    }

    function getInstrumentAndBarrierIds(uint8 amount) public pure returns (uint256[] memory, uint32[] memory) {
        uint256[] memory instrumentIds = new uint256[](amount);
        uint32[] memory barrierIds = new uint32[](amount);
        for (uint8 i = 0; i < amount; i++) {
            instrumentIds[i] = i;
            barrierIds[i] = i;
        }
        return (instrumentIds, barrierIds);
    }

    function setPriceBackupWithChecks(address _base, uint256 _timestamp, uint256 _price, BaseOracle _oracle) public {
        _oracle.setPriceBackup(_base, _timestamp, _price);
        (bool isDisputed, uint64 reportAt, uint128 price) = _oracle.historicalPrices(_base, _timestamp);
        assertEq(isDisputed, true);
        assertEq(reportAt, block.timestamp);
        assertEq(price, _price);
    }

    function setStableAssetWithChecks(address _asset, bool _isStableAsset, BaseOracle _oracle) public {
        _oracle.setStableAsset(_asset, _isStableAsset);
        assertEq(_oracle.stableAssets(_asset), _isStableAsset);
    }

    function setDisputePeriodWithChecks(address _base, uint256 _period, DisputableOracle _oracle) public {
        _oracle.setDisputePeriod(_base, _period);
        assertEq(_oracle.disputePeriod(_base), _period);
    }

    function defaultReportPrice(uint256 _priceToTest, uint64 _expiryToTest, PythOracle _oracle) public {
        bytes[] memory dummyPythUpdateData = new bytes[](1);
        dummyPythUpdateData[0] = bytes("0");
        bytes32[] memory dummyPriceFeedIds = new bytes32[](1);
        dummyPriceFeedIds[0] = WETH_PRICE_FEED;
        address[] memory assets = new address[](1);
        assets[0] = WETH;
        uint256[] memory pricesToTest = new uint256[](1);
        pricesToTest[0] = _priceToTest;
        PythStructs.PriceFeed[] memory resultPriceFeeds = new PythStructs.PriceFeed[](1);
        PythStructs.PriceFeed memory wethResult =
            getPythPriceFeedStruct(3000 * 10 ** 8, RANDOM_PYTH_CONF, -8, _expiryToTest, WETH_PRICE_FEED);
        resultPriceFeeds[0] = wethResult;
        reportPriceWithChecks(
            dummyPythUpdateData, dummyPriceFeedIds, _expiryToTest, pricesToTest, resultPriceFeeds, assets, _oracle
        );
    }

    function reportPriceWithChecks(
        bytes[] memory _dummyPythUpdateData,
        bytes32[] memory _dummyPriceFeedIds,
        uint64 _expiryToTest,
        uint256[] memory _pricesToTest,
        PythStructs.PriceFeed[] memory _resultPriceFeeds,
        address[] memory _assets,
        PythOracle _oracle
    ) public {
        reportPriceHelper(_dummyPythUpdateData, _dummyPriceFeedIds, _expiryToTest, _resultPriceFeeds, _oracle);
        checkPriceHelper(_expiryToTest, _pricesToTest, _assets, _oracle);
    }

    function reportPriceHelper(
        bytes[] memory _dummyPythUpdateData,
        bytes32[] memory _dummyPriceFeedIds,
        uint64 _expiryToTest,
        PythStructs.PriceFeed[] memory _resultPriceFeeds,
        PythOracle _oracle
    ) public {
        vm.mockCall(PYTH, abi.encodeWithSelector(IPyth.getUpdateFee.selector), abi.encode(1 wei));
        vm.mockCall(
            PYTH,
            1,
            abi.encodeWithSelector(
                IPyth.parsePriceFeedUpdates.selector, _dummyPythUpdateData, _dummyPriceFeedIds, _expiryToTest, _expiryToTest
            ),
            abi.encode(_resultPriceFeeds)
        );
        _oracle.reportPrice(_dummyPythUpdateData, _dummyPriceFeedIds, _expiryToTest);
        vm.clearMockedCalls();
    }

    function checkPriceHelper(uint64 _expiryToTest, uint256[] memory _pricesToTest, address[] memory _assets, PythOracle _oracle)
        public
    {
        for (uint16 i = 0; i < _assets.length; i++) {
            (bool isDisputed, uint64 reportAt, uint128 price) = _oracle.historicalPrices(_assets[i], _expiryToTest);
            assertEq(isDisputed, false);
            assertEq(reportAt, block.timestamp);
            assertEq(price, _pricesToTest[i]);
        }
    }
}
