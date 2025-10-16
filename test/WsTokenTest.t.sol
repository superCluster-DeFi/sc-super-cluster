// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BaseToken} from "../src/tokens/BaseToken.sol";
import {SToken} from "../src/tokens/SToken.sol";
import {WsToken} from "../src/tokens/WsToken.sol";

/**
 * @title WsToken.t.sol
 * @notice Tests for wrapping/unwrapping STOKEN (rebasing) to WsToken (non-rebasing)
 */
contract WsTokenTest is Test {
    BaseToken base;
    SToken sToken;
    WsToken wsToken;
    address user1;
    address user2;

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 1. Deploy BaseToken (underlying)
        base = new BaseToken("Base Token", "BASE", 18);

        // 2. Deploy SToken (rebasing)
        sToken = new SToken("Staked Token", "sTOKEN", address(base), address(base));

        // 3. Deploy WsToken (non-rebasing)
        wsToken = new WsToken(address(sToken));

        // 4. Mint base to users
        base.mint(user1, 1_000 ether);
        base.mint(user2, 1_000 ether);

        // 5. Give minting rights to user1 for simplicity
        sToken.setAuthorizedMinter(user1, true);
        sToken.setAuthorizedMinter(address(this), true);

        sToken.mint(address(this), 1e18);
        sToken.updateAssetsUnderManagement(2e18);
        vm.warp(block.timestamp + 1 days);
        sToken.rebase(1e18);
    }

    function testWrapAndUnwrapFlow() public {
        vm.startPrank(user1);

        // Mint 100 sToken to user1 (simulating stake)
        sToken.mint(user1, 100 ether);
        assertEq(sToken.balanceOf(user1), 100 ether, "Mint failed");

        // Approve WsToken to spend sToken
        sToken.approve(address(wsToken), type(uint256).max);

        // Wrap 100 sToken -> expect 100 wsToken (first time = 1:1)
        wsToken.wrap(100 ether);
        assertEq(wsToken.balanceOf(user1), 100 ether, "Initial wrap failed");
        assertEq(sToken.balanceOf(address(wsToken)), 100 ether, "Contract sToken balance mismatch");

        // Simulate time passing + rebase (+10%)
        vm.warp(block.timestamp + 1 days);
        sToken.rebase(110 ether); // increase total underlying

        // wsToken rate must increase
        uint256 rate = wsToken.stTokenPerWsToken();
        assertApproxEqRel(rate, 1.1e18, 0.001e18, "Rate should reflect rebase");

        // Unwrap: user burns 100 wsToken, receives 110 sToken
        uint256 beforeBalance = sToken.balanceOf(user1);
        wsToken.unwrap(100 ether);
        uint256 afterBalance = sToken.balanceOf(user1);
        uint256 received = afterBalance - beforeBalance;

        assertEq(received, 110 ether, "Unwrap yield mismatch");
        assertEq(wsToken.balanceOf(user1), 0, "User wsToken should be 0");

        vm.warp(block.timestamp + 1 days);
        sToken.rebase(1e18);
        vm.stopPrank();
    }

    function testUnwrapToRecipient() public {
        vm.startPrank(user1);

        // Mint + approve
        sToken.mint(user1, 50 ether);
        sToken.approve(address(wsToken), type(uint256).max);

        // Wrap
        wsToken.wrap(50 ether);
        assertEq(wsToken.balanceOf(user1), 50 ether, "Wrap failed");

        // Simulate +20% rebase
        sToken.rebase(60 ether);

        // Unwrap to another user
        wsToken.unwrapTo(50 ether, user2);
        assertEq(sToken.balanceOf(user2), 60 ether, "Recipient unwrap mismatch");
        assertEq(wsToken.balanceOf(user1), 0, "Sender wsToken should be burned");

        vm.warp(block.timestamp + 1 days);
        sToken.rebase(1e18);
        vm.stopPrank();
    }

    function testRateAndConversionFunctions() public {
        vm.startPrank(user1);

        sToken.mint(user1, 100 ether);
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(100 ether);

        vm.warp(block.timestamp + 1 days);

        // Initial conversion rates (1:1)
        assertEq(wsToken.stTokenPerWsToken(), 1e18);
        assertEq(wsToken.wsTokenPerStToken(), 1e18);

        // Rebase by +50%
        sToken.rebase(150 ether);

        // New conversion rates
        uint256 stPerWs = wsToken.stTokenPerWsToken();
        uint256 wsPerSt = wsToken.wsTokenPerStToken();

        assertApproxEqRel(stPerWs, 1.5e18, 0.001e18, "st/ws mismatch");
        assertApproxEqRel(wsPerSt, 0.6666e18, 0.001e18, "ws/st mismatch");

        vm.warp(block.timestamp + 1 days);
        sToken.rebase(1e18);
        vm.stopPrank();
    }

    function testCannotWrapZeroAmount() public {
        vm.expectRevert(bytes("Amount must be > 0"));
        wsToken.wrap(0);
        vm.warp(block.timestamp + 1 days);
        sToken.rebase(1e18);
    }

    function testCannotUnwrapWithoutBalance() public {
        vm.expectRevert(bytes("Insufficient wsToken balance"));
        wsToken.unwrap(1 ether);
        vm.warp(block.timestamp + 1 days);
        sToken.rebase(1e18);
    }
}
