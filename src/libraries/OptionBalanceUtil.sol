// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TokenIdUtil} from "./TokenIdUtil.sol";
import {OptionBalance} from "../config/types.sol";

/**
 * Operations on OptionBalance struct
 */
library OptionBalanceUtil {
    using TokenIdUtil for uint256;

    /**
     * @dev create a new OptionBalance array with 1 more element
     * @param x balance array
     * @param v new value to add
     * @return y new balance array
     */
    function append(OptionBalance[] memory x, OptionBalance memory v) internal pure returns (OptionBalance[] memory y) {
        y = new OptionBalance[](x.length + 1);
        uint256 i;
        for (i; i < x.length;) {
            y[i] = x[i];
            unchecked {
                ++i;
            }
        }
        y[i] = v;
    }

    /**
     * @dev check if a balance object for collateral id already exists
     * @param x option balance array
     * @param e engine id to search
     * @param v collateral id to search
     * @return f true if found
     * @return b OptionBalance object
     * @return i index of the found entry
     */
    function find(OptionBalance[] memory x, uint8 e, uint8 v) internal pure returns (bool f, OptionBalance memory b, uint256 i) {
        for (i; i < x.length;) {
            if (x[i].tokenId.parseEngineId() == e && x[i].tokenId.parseCollateralId() == v) {
                b = x[i];
                f = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev return the index of an element option balance array
     * @param x option balance array
     * @param e engine id to search
     * @param v collateral id to search
     * @return f true if found
     * @return i index of the found entry
     */
    function indexOf(OptionBalance[] memory x, uint8 e, uint8 v) internal pure returns (bool f, uint256 i) {
        for (i; i < x.length;) {
            if (x[i].tokenId.parseEngineId() == e && x[i].tokenId.parseCollateralId() == v) {
                f = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev remove index y from option balance array
     * @param x balance array
     * @param i index to remove
     */
    function remove(OptionBalance[] storage x, uint256 i) internal {
        if (i >= x.length) return;
        x[i] = x[x.length - 1];
        x.pop();
    }

    /**
     * @dev checks if balances are empty
     */
    function isEmpty(OptionBalance[] memory x) internal pure returns (bool e) {
        e = true;
        for (uint256 i; i < x.length;) {
            if (x[i].amount > 0) {
                e = false;
                break;
            }
            unchecked {
                ++i;
            }
        }
    }
}
