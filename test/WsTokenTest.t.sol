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

        // 1. Deploy BaseToken (e.g. underlying token)
        base = new BaseToken("Base Token", "BASE", 18);

        // 2. Deploy SToken (rebasing staking token)
        sToken = new SToken("Staked Token", "sTOKEN", address(base), address(base));

        // 3. Deploy WsToken (wrapped non-rebasing)
        wsToken = new WsToken(address(sToken));

        // 4. Mint BaseToken to user
        base.mint(user1, 1_000 ether);
        base.mint(user2, 1_000 ether);

        // 5. Approve sToken for staking
        vm.startPrank(user1);
        base.approve(address(sToken), type(uint256).max);

        vm.stopPrank();

        // 6. Stake 100 base tokens
        sToken.setAuthorizedMinter(user1, true);
    }

    function testWrapAndUnwrapFlow() public {
        vm.startPrank(user1);

        // Stake 100 base tokens -> get 100 sToken
        sToken.stake(100 ether);
        assertEq(sToken.balanceOf(user1), 100 ether, "Initial sToken mint failed");

        // Approve wsToken to wrap
        sToken.approve(address(wsToken), type(uint256).max);

        // Wrap 100 sToken -> get 100 wsToken (1:1)
        wsToken.wrap(100 ether);
        assertEq(wsToken.balanceOf(user1), 100 ether, "Initial wrap failed");

        // After wrapping, sToken inside wsToken contract should be 100
        assertEq(sToken.balanceOf(address(wsToken)), 100 ether, "Contract STOKEN balance mismatch");

        // Simulate time passing to allow rebase
        vm.warp(block.timestamp + 1 days);

        // Simulate rebase (increase sToken supply by +10%)
        sToken.rebase(110 ether); // total up by 10%

        // Check the exchange rate
        uint256 rate = wsToken.stTokenPerWsToken();
        assertGt(rate, 1e18, "Rate should increase after rebase");

        // Unwrap all wsToken -> should get more sToken (110)
        uint256 beforeSToken = sToken.balanceOf(user1);
        wsToken.unwrap(100 ether);
        uint256 afterSToken = sToken.balanceOf(user1);

        uint256 received = afterSToken - beforeSToken;
        assertEq(received, 110 ether, "Unwrap should yield rebased amount");

        vm.stopPrank();
    }

    function testUnwrapToRecipient() public {
        vm.startPrank(user1);
        vm.warp(block.timestamp + 1 days);

        // Stake and wrap
        sToken.stake(50 ether);
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(50 ether);

        // Rebase to +20%
        sToken.rebase(60 ether);

        // Unwrap to user2
        wsToken.unwrapTo(50 ether, user2);
        assertEq(sToken.balanceOf(user2), 60 ether, "Recipient unwrap mismatch");

        vm.stopPrank();
    }

    function testCannotWrapZeroAmount() public {
        vm.expectRevert(bytes("Amount must be > 0"));
        wsToken.wrap(0);
    }

    function testCannotUnwrapWithoutBalance() public {
        vm.expectRevert(bytes("Insufficient wsToken balance"));
        wsToken.unwrap(1 ether);
    }
}
