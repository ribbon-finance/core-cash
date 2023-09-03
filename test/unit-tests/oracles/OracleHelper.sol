// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseOracle} from "../../../src/core/oracles/abstract/BaseOracle.sol";
import {DisputableOracle} from "../../../src/core/oracles/abstract/DisputableOracle.sol";

// import test base and helpers.
import "forge-std/Test.sol";

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

    // Pyth Data
    // ETH price update for 1692706735
    bytes public constant PYTH_UPDATE_SAMPLE_DATA =
        hex"01000000030d00a4295499e986e4a23dbfc3e63f7c7d4a0ead2789ada872552bca7cc5e47fc9481f26ee5f36c53fb64015256a997761644a59c32e41f0a336d81df5198f51932b00011ef606b75df455fc2247d981e9ee569c9adf99f7ddd8d7eb88f4ffe0fc68895705a820fe469b369ca4477df60559bca87fe4c026d876239d438c37d4a42ad39301027e9803d70ce280c4b00ce58ad49094f07902b4b20cab57d1f66cc18de17a8f6e420c3469dc2714ae62a1aceb68c72e7c99e6d65f27c495a8ba9b7ca29854604c010437dc82377abd35ce82df1ad27ad09db38460b746762a9d4c040c3b4a261005ea34db60f583cf2aa37daaf1ac91fafae8f2684a6fbb2a01497a97b7e1fe1b36f401095b06758341f4687633ce74e272b6f554b108a14c9cdafb849b57159353add8e319c5f58f8c8952f247b5165c065d8a5f704449e5300e5d13bdcbe0d86fa06a60000a9a14a5d226b23c90e5903a98cd9e40a4b21fbe7ebe2c7d6363746b6e0126997921c13090d57ac31b2eb37583d8519bae95936cec1049fdc506c69eea8de2fa1e000bf7b18e2f07c8fcb75f0b0b972ec260dfcd80cf322c5ce2f20ecec2c9f1d5534922b3aeaef6829a9d35996e4b35da340f99b8c9786418e2ec06283f2556f8c283000d37d053ad5810ad4be992797eb84b4948e42f29998ecfc6d0827c231465d718424be5cdb828d66a7dd3bd10009aae11723d66d7226264597993a041407cb7172a000e4780626cdb6d9d4c9a9a87ec44f6d897d7109ea99f63cb84cd3400f433fb2ea55b32b38ed230ff91df55a6486c5df6dace3f479cf91c77ae0dc1983f9bd350f8010fa6f70e856953a69c26e636f05ca714b49c04cd149738063fb2db5f797b5b66113da2843b88782bc5977a25fb4180f02c9098b13d024871467c701263285bf8af00106195eefe9b9bc864c7d059854b7afc671ad55873e879bd496fd9bca31fd2181d11ec29f387217864c7dbd36b9b26ec3f0150e3cf28dbfa7bc354aa21d54da8710111e0273c6969bc596e7ce0c1128059b35c3a873b2e3061cf4a706ee43c5bf6b71e3e03d9438f7ed74ac9d56c68645421b962b1de8e819c5023d1fa399e1d16856600123e6f018504d27c4cc2a5a702b7e3fc2415c6ce7767681b019fad37eac40edbf72eaf799d20333ddd44a9bbe503adb901505f09d673648a32b0a6928e3327dc740064e4a7af00000000001af8cd23c2ab91237730770bbea08d61005cdda0984348f3f6eecb559638c0bba0000000002448d4e30150325748000300010001020005009d04028fba493a357ecde648d51375a445ce1cb9681da1ea11e562b53522a5d3877f981f906d7cfe93f618804f1de89e0199ead306edc022d3230b3e8305f391b000000026b15c979f0000000007a6c596fffffff800000026acb69c700000000008dff3a4010000000c0000000f0000000064e4a7af0000000064e4a7af0000000064e4a7ae00000026b15ecc1b0000000007a8fa120000000064e4a7aee6c020c1a15366b779a8c870e065023657c88c82b82d58a9fe856896a4034b0415ecddd26d49e1a8f1de9376ebebc03916ede873447c1255d2d5891b92ce57170000002880e7d79c000000001170978bfffffff8000000287d7eba08000000000e5de38a010000000a0000000b0000000064e4a7af0000000064e4a7af0000000064e4a7ae0000002880da588800000000117e169f0000000064e4a7aec67940be40e0cc7ffaa1acb08ee3fab30955a197da1ec297ab133d4d43d86ee6ff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace00000026bbdf75230000000006a82eaffffffff800000026b690c068000000000575e3ff010000001d000000200000000064e4a7af0000000064e4a7af0000000064e4a7ae00000026bb5f41a800000000063cfe970000000064e4a7ae8d7c0971128e8a4764e757dedb32243ed799571706af3a68ab6a75479ea524ff846ae1bdb6300b817cee5fdee2a6da192775030db5615b94a465f53bd40850b500000026c7bfdf68000000000be25ca5fffffff800000026c9969c00000000000b0ddffd010000000d0000000d0000000064e4a7af0000000064e4a7af0000000064e4a7ae00000026c7bfdf68000000000be25ca50000000064e4a7ae543b71a4c292744d3fcf814a2ccda6f7c00f283d457f83aa73c41e9defae034ba0255134973f4fdf2f8f7808354274a3b1ebc6ee438be898d045e8b56ba1fe1300000000000000000000000000000000fffffff8000000000000000000000000000000000000000003000000080000000064e4a7af0000000064e4a7ae0000000000000000000000000000000000000000000000000000000000000000";
    uint32 public constant PYTH_UPDATE_SAMPLE_TIMESTAMP = 1692706735;

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
}
