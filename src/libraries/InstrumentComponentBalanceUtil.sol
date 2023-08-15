// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {InstrumentComponentBalance} from "../config/types.sol";

/**
 * Operations on InstrumentComponentBalance struct
 */
library InstrumentComponentBalanceUtil {
    /**
     * @dev create a new InstrumentComponentBalance array with 1 more element
     * @param x balance array
     * @param v new value to add
     * @return y new balance array
     */
    function append(InstrumentComponentBalance[] memory x, InstrumentComponentBalance memory v)
        internal
        pure
        returns (InstrumentComponentBalance[] memory y)
    {
        y = new InstrumentComponentBalance[](x.length + 1);
        uint256 i;
        for (i; i < x.length;) {
            y[i] = x[i];
            unchecked {
                ++i;
            }
        }
        y[i] = v;
    }
}
