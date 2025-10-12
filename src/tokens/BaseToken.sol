// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract BaseToken {
    function name() external view virtual returns (string memory);

    function symbol() external view virtual returns (string memory);

    function decimals() external view virtual returns (uint8);
}
