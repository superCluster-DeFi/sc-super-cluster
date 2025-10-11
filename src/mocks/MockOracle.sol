// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracle} from "./interfaces/IOracle.sol";

contract MockOracle is IOracle {
    uint256 private _price;

    constructor() {
        _price = 1e18;
    }

    function price() external view override returns (uint256) {
        return _price;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }
}
