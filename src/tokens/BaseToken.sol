// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title BaseToken - Simple ERC20 used as the underlying asset for staking
contract BaseToken is ERC20 {
    address public owner;

    constructor(string memory name_, string memory symbol_, uint8 /*decimals_*/) ERC20(name_, symbol_) {
        owner = msg.sender;
    }

    /// @notice Mint tokens to any address (for testing)
    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Not owner");
        _mint(to, amount);
    }
}
