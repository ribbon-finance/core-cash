// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {TokenIdUtil} from "../../src/libraries/TokenIdUtil.sol";
import "../../src/config/constants.sol";
import "../../src/config/errors.sol";
import "../../src/config/types.sol";

/**
 * @dev tester contract to make coverage works
 */
contract TokenIdUtilTester {
    function getTokenId(TokenType tokenType, uint40 productId, uint64 expiry, uint64 longStrike, uint64 shortStrike)
        external
        pure
        returns (uint256 tokenId)
    {
        uint256 result = TokenIdUtil.getTokenId(tokenType, productId, expiry, longStrike, shortStrike);
        return result;
    }

    function convertBarrierObservationFrequencyType(BarrierObservationFrequencyType frequency) external pure returns (uint256) {
        uint256 result = TokenIdUtil.convertBarrierObservationFrequencyType(frequency);
        return result;
    }

    function isExpired(uint256 tokenId) external view returns (bool expired) {
        bool result = TokenIdUtil.isExpired(tokenId);
        return result;
    }
}

/**
 * Tests to improve coverage
 */
contract TokenIdLibTest is Test {
    uint256 public constant base = UNIT;

    TokenIdUtilTester tester;

    function setUp() public {
        tester = new TokenIdUtilTester();
    }

    function testConvertBarrierObservationFrequencyType() public {
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_DAY), 1 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_WEEK), 7 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.TWO_WEEKS), 14 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_MONTH), 30 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.TWO_MONTHS), 60 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.THREE_MONTHS), 90 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.SIX_MONTHS), 180 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.NINE_MONTHS), 270 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.ONE_YEAR), 365 days);
        assertEq(tester.convertBarrierObservationFrequencyType(BarrierObservationFrequencyType.NONE), 1);
    }

    function testIsExpired() public {
        vm.warp(1671840000);

        uint64 expiry = uint64(block.timestamp + 1);
        uint256 tokenId = tester.getTokenId(TokenType.PUT, 0, expiry, 0, 0);
        assertEq(tester.isExpired(tokenId), false);

        uint64 expiry2 = uint64(block.timestamp - 1);
        uint256 tokenId2 = tester.getTokenId(TokenType.PUT, 0, expiry2, 0, 0);
        assertEq(tester.isExpired(tokenId2), true);
    }
}
