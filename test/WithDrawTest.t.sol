// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Withdraw} from "../src/tokens/WithDraw.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Mock Tokens
contract BaseToken is ERC20("BaseToken", "BASE") {
    constructor() {
        _mint(msg.sender, 1_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

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

/// Test Withdraw.sol
contract WithdrawTest is Test {
    Withdraw public withdraw;
    BaseToken public baseToken;
    MockSToken public sToken;

    address public owner;
    address public user1;
    address public user2;
    address public superCluster; // mock SuperCluster

    uint256 public constant DELAY = 1 days;

    function setUp() public {
        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        superCluster = vm.addr(3);

        console.log("=== Setting up environment ===");

        baseToken = new BaseToken();
        sToken = new MockSToken();

        // constructor(address _sToken, address _baseToken, address _superCluster, uint256 _withdrawDelay)
        withdraw = new Withdraw(address(sToken), address(baseToken), superCluster, DELAY);

        sToken.mint(user1, 1000 ether);
        baseToken.mint(owner, 1000 ether);

        vm.startPrank(user1);
        sToken.approve(address(withdraw), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(owner);
        baseToken.approve(address(withdraw), type(uint256).max);
        vm.stopPrank();

        baseToken.approve(address(withdraw), type(uint256).max);

        console.log("BaseToken deployed at:", address(baseToken));
        console.log("SToken deployed at:", address(sToken));
        console.log("Withdraw contract deployed at:", address(withdraw));
        console.log("===============================");
    }

    /// requestWithdraw()
    function test_RequestWithdraw() public {
        vm.startPrank(user1);
        uint256 requestId = withdraw.requestWithdraw(100 ether);
        vm.stopPrank();

        (address reqUser, uint256 sAmount,,,, bool finalized, bool claimed) = withdraw.getRequest(requestId);
        assertEq(reqUser, user1);
        assertEq(sAmount, 100 ether);
        assertFalse(finalized);
        assertFalse(claimed);
    }

    /// autoRequest() — only SuperCluster
    function test_AutoRequest_FromSuperCluster() public {
        vm.startPrank(superCluster);
        uint256 requestId = withdraw.autoRequest(user1, 50 ether);
        vm.stopPrank();

        (address reqUser, uint256 sAmount,,,, bool finalized, bool claimed) = withdraw.getRequest(requestId);
        assertEq(reqUser, user1);
        assertEq(sAmount, 50 ether);
        assertFalse(finalized);
        assertFalse(claimed);
    }

    /// fund()
    function test_FundBaseTokens() public {
        withdraw.fund(500 ether);
        uint256 contractBal = baseToken.balanceOf(address(withdraw));
        assertEq(contractBal, 500 ether);
    }

    /// finalizeWithdraw()
    function test_FinalizeWithdraw() public {
        vm.startPrank(user1);
        uint256 requestId = withdraw.requestWithdraw(200 ether);
        vm.stopPrank();

        withdraw.fund(500 ether);
        withdraw.finalizeWithdraw(requestId, 200 ether);

        (,, uint256 baseAmount,, uint256 availableAt, bool finalized, bool claimed) = withdraw.getRequest(requestId);
        assertEq(baseAmount, 200 ether);
        assertTrue(finalized);
        assertFalse(claimed);
        assertGt(availableAt, 0);
    }

    /// claim() after delay
    function test_ClaimAfterFinalizeAndDelay() public {
        vm.startPrank(user1);
        uint256 requestId = withdraw.requestWithdraw(300 ether);
        vm.stopPrank();

        withdraw.fund(500 ether);
        withdraw.finalizeWithdraw(requestId, 300 ether);

        vm.warp(block.timestamp + DELAY + 1);

        vm.startPrank(user1);
        uint256 beforeBase = baseToken.balanceOf(user1);
        withdraw.claim(requestId);
        vm.stopPrank();

        uint256 afterBase = baseToken.balanceOf(user1);
        assertEq(afterBase - beforeBase, 300 ether);
    }

    /// cancelRequest() by owner
    function test_CancelRequestByOwner() public {
        vm.startPrank(user1);
        uint256 requestId = withdraw.requestWithdraw(150 ether);
        vm.stopPrank();

        uint256 beforeBalance = sToken.balanceOf(user1);
        withdraw.cancelRequest(requestId);
        uint256 afterBalance = sToken.balanceOf(user1);

        assertGt(afterBalance, beforeBalance);

        (address reqUser,,,,,,) = withdraw.getRequest(requestId);
        assertEq(reqUser, address(0));
    }

    /// emergencyWithdrawBase()
    function test_EmergencyWithdrawBase() public {
        withdraw.fund(100 ether);
        uint256 beforeOwner = baseToken.balanceOf(owner);
        withdraw.emergencyWithdrawBase(50 ether, owner);
        uint256 afterOwner = baseToken.balanceOf(owner);
        assertEq(afterOwner, beforeOwner + 50 ether);
    }

    /// emergencyWithdrawSToken()
    function test_EmergencyWithdrawSToken() public {
        vm.startPrank(user1);
        withdraw.requestWithdraw(100 ether);
        vm.stopPrank();

        uint256 beforeOwner = sToken.balanceOf(owner);
        withdraw.emergencyWithdrawSToken(50 ether, owner);
        uint256 afterOwner = sToken.balanceOf(owner);
        assertEq(afterOwner, beforeOwner + 50 ether);
    }
}
