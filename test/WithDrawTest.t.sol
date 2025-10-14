// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Withdraw} from "../src/tokens/WithDraw.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mock base token (e.g., like USDC)
contract BaseToken is ERC20("BaseToken", "BASE") {
    constructor() {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Mock SToken (minimal functions for Withdraw test)
contract MockSToken is ERC20("SToken", "STK") {
    constructor() {
        _mint(msg.sender, 1_000_000 ether);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title WithdrawTest
/// @notice Forge test suite for Withdraw.sol
contract WithDrawTest is Test {
    Withdraw public withdraw;
    MockSToken public sToken;
    BaseToken public baseToken;
    address user = address(0x123);
    uint256 constant DELAY = 1 days;

    function setUp() public {
        console.log("=== Setting up environment ===");
        sToken = new MockSToken();
        baseToken = new BaseToken();
        withdraw = new Withdraw(address(sToken), address(baseToken), DELAY);

        sToken.mint(user, 100 ether);
        baseToken.mint(address(this), 1_000 ether);

        vm.startPrank(user);
        sToken.approve(address(withdraw), type(uint256).max);
        vm.stopPrank();

        console.log("Setup complete");
        console.log("User sToken balance:", sToken.balanceOf(user) / 1e18, "STK");
        console.log("Withdraw contract address:", address(withdraw));
        console.log("");
    }

    function testFullWithdrawFlow() public {
        console.log("=== User requests withdraw ===");
        vm.startPrank(user);
        uint256 id = withdraw.requestWithdraw(10 ether);
        vm.stopPrank();
        console.log("Request ID:", id);
        console.log("sToken balance after request:", sToken.balanceOf(user) / 1e18, "STK");

        (address reqUser,, uint256 baseAmount,, uint256 availableAt, bool finalized, bool claimed) =
            withdraw.getRequest(id);
        console.log("Request user:", reqUser);
        console.log("Initial baseAmount:", baseAmount);
        console.log("Finalized:", finalized, "| Claimed:", claimed);
        console.log("");

        console.log("=== Owner funds base token ===");
        uint256 beforeFund = baseToken.balanceOf(address(withdraw));
        baseToken.approve(address(withdraw), 10 ether);
        withdraw.fund(10 ether);
        uint256 afterFund = baseToken.balanceOf(address(withdraw));
        console.log("BaseToken in withdraw before:", beforeFund / 1e18, "after:", afterFund / 1e18);
        console.log("");

        console.log("=== Owner finalizes withdraw ===");
        withdraw.finalizeWithdraw(id, 10 ether);
        (,, baseAmount,, availableAt, finalized, claimed) = withdraw.getRequest(id);
        console.log("BaseAmount set to:", baseAmount / 1e18);
        console.log("Finalized:", finalized);
        console.log("Available at:", availableAt);
        console.log("");

        console.log("=== Time travel to unlock claim ===");
        vm.warp(block.timestamp + DELAY + 1);
        console.log("New block.timestamp:", block.timestamp);
        console.log("");

        console.log("=== User claims base token ===");
        uint256 userBalanceBefore = baseToken.balanceOf(user);
        vm.startPrank(user);
        withdraw.claim(id);
        vm.stopPrank();
        uint256 userBalanceAfter = baseToken.balanceOf(user);
        console.log("Base token user before:", userBalanceBefore / 1e18, "after:", userBalanceAfter / 1e18);
        console.log("Withdraw flow completed");
    }
}
