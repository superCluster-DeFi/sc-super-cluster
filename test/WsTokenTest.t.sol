// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {MockUSDC} from "../src/mocks/tokens/MockUSDC.sol";
import {SToken} from "../src/tokens/SToken.sol";
import {WsToken} from "../src/tokens/WsToken.sol";

contract WsTokenTest is Test {
    MockUSDC mockUsdc;
    SToken sToken;
    WsToken wsToken;
    address user1;
    address user2;

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Deploy contracts
        mockUsdc = new MockUSDC();
        sToken = new SToken("Staked Token", "sTOKEN", address(mockUsdc));
        wsToken = new WsToken("Wrap Staked Token", "wsUSDC", address(sToken));

        // Mint mockUsdc to users
        mockUsdc.mint(user1, 1_000 ether);
        mockUsdc.mint(user2, 1_000 ether);

        // Set authorized minters
        sToken.setAuthorizedMinter(user1, true);
        sToken.setAuthorizedMinter(address(this), true);
    }

    function testWrapAndUnwrapFlow() public {
        vm.startPrank(user1);

        // Mint 100 sToken to user1
        sToken.mint(user1, 100 ether);
        assertEq(sToken.balanceOf(user1), 100 ether, "Mint failed");

        // Approve and wrap
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(100 ether);

        assertEq(wsToken.balanceOf(user1), 100 ether, "Initial wrap failed");
        assertEq(sToken.balanceOf(address(wsToken)), 100 ether, "Contract sToken balance mismatch");

        vm.stopPrank();

        // Simulate rebase: increase underlying by 10%
        // Current AUM = 100 ether, increase to 110 ether
        vm.warp(block.timestamp + 1 days);
        uint256 newAUM = sToken.getTotalAssetsUnderManagement() + 10 ether;
        sToken.forceRebase(newAUM);

        // Check rate increased
        uint256 rate = wsToken.stTokenPerWsToken();
        assertApproxEqRel(rate, 1.1e18, 0.01e18, "Rate should reflect rebase"); // 1% tolerance

        // Unwrap: user burns 100 wsToken, receives ~110 sToken
        vm.startPrank(user1);
        uint256 beforeBalance = sToken.balanceOf(user1);
        wsToken.unwrap(100 ether);
        uint256 afterBalance = sToken.balanceOf(user1);
        uint256 received = afterBalance - beforeBalance;

        assertApproxEqRel(received, 110 ether, 0.01e18, "Unwrap yield mismatch"); // 1% tolerance
        assertEq(wsToken.balanceOf(user1), 0, "User wsToken should be 0");
        vm.stopPrank();
    }

    function testUnwrapToRecipient() public {
        vm.startPrank(user1);

        // Mint and wrap
        sToken.mint(user1, 50 ether);
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(50 ether);

        assertEq(wsToken.balanceOf(user1), 50 ether, "Wrap failed");
        vm.stopPrank();

        // Simulate +20% rebase
        vm.warp(block.timestamp + 1 days);
        uint256 newAUM = sToken.getTotalAssetsUnderManagement() + 10 ether; // 50 + 10 = 60
        sToken.forceRebase(newAUM);

        // Unwrap to user2
        vm.prank(user1);
        wsToken.unwrapTo(50 ether, user2);

        assertApproxEqRel(sToken.balanceOf(user2), 60 ether, 0.01e18, "Recipient unwrap mismatch");
        assertEq(wsToken.balanceOf(user1), 0, "Sender wsToken should be burned");
    }

    function testRateAndConversionFunctions() public {
        // Start with clean state
        sToken.mint(user1, 100 ether);

        vm.startPrank(user1);
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(100 ether);
        vm.stopPrank();

        // Initial rates should be 1:1
        assertEq(wsToken.stTokenPerWsToken(), 1e18, "Initial rate should be 1:1");
        assertEq(wsToken.wsTokenPerStToken(), 1e18, "Initial rate should be 1:1");

        // Simulate +50% rebase
        vm.warp(block.timestamp + 1 days);
        uint256 newAUM = sToken.getTotalAssetsUnderManagement() + 50 ether; // 100 + 50 = 150
        sToken.forceRebase(newAUM);

        // Check new rates
        uint256 stPerWs = wsToken.stTokenPerWsToken();
        uint256 wsPerSt = wsToken.wsTokenPerStToken();

        assertApproxEqRel(stPerWs, 1.5e18, 0.01e18, "st/ws mismatch"); // 1% tolerance
        assertApproxEqRel(wsPerSt, 0.6666e18, 0.02e18, "ws/st mismatch"); // 2% tolerance
    }

    function testCannotWrapZeroAmount() public {
        vm.expectRevert(bytes("Amount must be > 0"));
        wsToken.wrap(0);
    }

    function testCannotUnwrapWithoutBalance() public {
        vm.expectRevert(bytes("Insufficient wsToken balance"));
        vm.prank(user1);
        wsToken.unwrap(1 ether);
    }

    function testMultipleUsersWrapping() public {
        // User1 wraps first
        sToken.mint(user1, 100 ether);
        vm.startPrank(user1);
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(100 ether);
        vm.stopPrank();

        // Simulate rebase +50%
        vm.warp(block.timestamp + 1 days);
        uint256 newAUM = sToken.getTotalAssetsUnderManagement() + 50 ether;
        sToken.forceRebase(newAUM);

        // User2 wraps after rebase
        sToken.mint(user2, 150 ether);
        vm.startPrank(user2);
        sToken.approve(address(wsToken), type(uint256).max);
        wsToken.wrap(150 ether);
        vm.stopPrank();

        // User2 should receive less wsToken (because rate increased)
        uint256 user2WsBalance = wsToken.balanceOf(user2);
        assertApproxEqRel(user2WsBalance, 100 ether, 0.02e18, "User2 wsToken mismatch");

        uint256 user1Balance = wsToken.balanceOf(user1);
        uint256 user2Balance = wsToken.balanceOf(user2);

        // Both unwrap and check proportional returns
        vm.prank(user1);
        wsToken.unwrap(user1Balance);

        vm.prank(user2);
        wsToken.unwrap(user2Balance);

        // Both should have ~150 sToken each
        assertApproxEqRel(sToken.balanceOf(user1), 150 ether, 0.02e18, "User1 final balance");
        assertApproxEqRel(sToken.balanceOf(user2), 150 ether, 0.02e18, "User2 final balance");
    }
}
