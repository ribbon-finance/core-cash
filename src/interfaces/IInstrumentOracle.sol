// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

interface IInstrumentOracle is IOracle {
    function barrierUpdates(uint256, uint32) external view returns (uint256[] memory);
}
