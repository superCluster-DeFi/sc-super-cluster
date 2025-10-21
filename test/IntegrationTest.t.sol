// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {SuperClusterTest, console, MockIDRX, Withdraw} from "./SuperClusterTest.t.sol";

contract IntegrationTest is SuperClusterTest {
    function test_Integration_FullUserFlow() public {
        console.log("=== Testing Full User Flow ===");

        // User deposits to SuperCluster
        vm.startPrank(user1);
        idrx.approve(address(superCluster), DEPOSIT_AMOUNT);
        superCluster.deposit(address(pilot), address(idrx), DEPOSIT_AMOUNT);

        uint256 sTokenBalance = sToken.balanceOf(user1);
        assertEq(sTokenBalance, DEPOSIT_AMOUNT);
        console.log("User deposited and received sTokens");
        vm.stopPrank();

        // Check adapter balances
        uint256 aaveBalance = aaveAdapter.getBalance();
        uint256 morphoBalance = morphoAdapter.getBalance();

        assertGt(aaveBalance, 0);
        assertGt(morphoBalance, 0);
        console.log("Pilot invested in adapters");
        console.log("Aave balance:", aaveBalance);
        console.log("Morpho balance:", morphoBalance);

        // Check total AUM calculation
        uint256 totalAUM = superCluster.calculateTotalAUM();
        assertGt(totalAUM, 0);
        console.log("Total AUM calculated:", totalAUM);

        // Trigger rebase
        vm.warp(block.timestamp + 1 days);
        idrx.mint(address(pilot), 100e18); // Simulate some yield in pilot
        superCluster.rebase();
        console.log("Rebase completed");

        // Simulate yield and rebase again
        idrx.mint(address(pilot), 100e18); // 10% yield on Aave
        idrx.mint(address(pilot), 50e18); // 5% yield on Morpho

        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();

        // User's sToken balance should increase due to rebase
        uint256 newSTokenBalance = sToken.balanceOf(user1);
        assertGt(newSTokenBalance, sTokenBalance, "Balance should increase after yield");
        console.log("After yield - sToken balance:", newSTokenBalance);

        uint256 idrxBeforeWithdraw = idrx.balanceOf(user1);

        // --- Withdraw flow ---
        vm.startPrank(user1);
        superCluster.withdraw(address(idrx), newSTokenBalance);
        vm.stopPrank();

        Withdraw withdrawManager = Withdraw(superCluster.withdrawManager());

        // Fund WithdrawManager with enough IDRX for the withdrawal (including yield)
        vm.prank(owner);
        idrx.transfer(address(withdrawManager), newSTokenBalance);
        console.log("WithdrawManager balance after transfer:", idrx.balanceOf(address(withdrawManager)));

        // Get latest requestId for user1
        uint256 requestId = withdrawManager.nextRequestId() - 1;

        // Finalize and claim
        superCluster.finalizeWithdraw(requestId, newSTokenBalance);
        superCluster.claim(requestId);

        uint256 sTokenAfterWithdraw = sToken.balanceOf(user1);
        assertEq(sTokenAfterWithdraw, 0, "User sToken should be zero after withdraw");

        uint256 idrxAfterWithdraw = idrx.balanceOf(user1) - idrxBeforeWithdraw;
        console.log("User1 IDRX after withdraw:", idrxAfterWithdraw);
        assertApproxEqRel(
            idrxAfterWithdraw,
            newSTokenBalance,
            1e16,
            "User1 should receive IDRX equal to sToken withdrawn (including yield)"
        );

        console.log("=== Full Integration Test Complete ===");
    }

    function test_Integration_MultipleUsers() public {
        console.log("=== Testing Multiple Users ===");

        uint256 depositAmount1 = 1000e18;
        uint256 depositAmount2 = 2000e18;

        // User 1 deposits
        vm.startPrank(user1);
        idrx.approve(address(superCluster), depositAmount1);
        superCluster.deposit(address(pilot), address(idrx), depositAmount1);
        vm.stopPrank();

        // User1 initial balance
        uint256 user1Balance = sToken.balanceOf(user1);
        assertEq(user1Balance, depositAmount1, "User1 balance should be 1:1 on first deposit");

        // Simulate yield: add yield to Aave
        idrx.mint(address(pilot), 150e18); // 15% yield

        // Rebase after yield
        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();

        // User1 balance should increase after yield
        uint256 user1BalanceAfterYield = sToken.balanceOf(user1);
        assertGt(user1BalanceAfterYield, depositAmount1, "User1 balance should increase after yield");
        console.log("User1 balance after first yield:", user1BalanceAfterYield);

        // User 2 deposits after yield
        vm.startPrank(user2);
        idrx.approve(address(superCluster), depositAmount2);
        superCluster.deposit(address(pilot), address(idrx), depositAmount2);
        vm.stopPrank();

        // User2 should get 1:1 sToken
        uint256 user2Balance = sToken.balanceOf(user2);
        console.log("User2 balance received:", user2Balance);
        console.log("Deposit amount 2:", depositAmount2);
        assertApproxEqRel(user2Balance, depositAmount2, 1e16); // 1% tolerance
        console.log("User2 balance received:", user2Balance);

        // Check balances after user2 deposit
        uint256 balance1 = sToken.balanceOf(user1);
        uint256 balance2 = sToken.balanceOf(user2);
        console.log("User1 sToken balance:", balance1);
        console.log("User2 sToken balance:", balance2);

        // Simulate another yield
        idrx.mint(address(pilot), 200e18); // Additional yield

        // Rebase again
        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();

        // Check new balances (should increase proportionally)
        uint256 newBalance1 = sToken.balanceOf(user1);
        uint256 newBalance2 = sToken.balanceOf(user2);
        console.log("User1 balance after second yield:", newBalance1);
        console.log("User2 balance after second yield:", newBalance2);

        assertGt(newBalance1, balance1, "User1 balance should increase after second yield");
        assertGt(newBalance2, balance2, "User2 balance should increase after second yield");

        // Withdraw both users
        vm.startPrank(user1);
        superCluster.withdraw(address(idrx), newBalance1);
        vm.stopPrank();
        vm.startPrank(user2);
        superCluster.withdraw(address(idrx), newBalance2);
        vm.stopPrank();

        assertEq(sToken.balanceOf(user1), 0, "User1 sToken should be zero after withdraw");
        assertLe(sToken.balanceOf(user2), 1, "User2 sToken should be zero (or 1 wei) after withdraw");

        console.log("Multiple users test complete");
        console.log("User1 balance after yield:", newBalance1);
        console.log("User2 balance after yield:", newBalance2);
    }

    function test_Integration_PilotStrategy() public {
        console.log("=== Testing Pilot Strategy Management ===");

        // Set up initial strategy
        address[] memory adapters = new address[](2);
        uint256[] memory allocations = new uint256[](2);
        adapters[0] = address(aaveAdapter);
        adapters[1] = address(morphoAdapter);
        allocations[0] = 7000; // 70% Aave
        allocations[1] = 3000; // 30% Morpho

        pilot.setPilotStrategy(adapters, allocations);

        // Transfer funds to pilot
        bool status = idrx.transfer(address(pilot), DEPOSIT_AMOUNT);
        require(status, "Transfer failed");

        // Invest using strategy
        pilot.invest(DEPOSIT_AMOUNT, adapters, allocations);

        // Check allocation
        uint256 aaveBalance = aaveAdapter.getBalance();
        uint256 morphoBalance = morphoAdapter.getBalance();

        uint256 expectedAave = (DEPOSIT_AMOUNT * 7000) / 10000;
        uint256 expectedMorpho = (DEPOSIT_AMOUNT * 3000) / 10000;

        assertApproxEqRel(aaveBalance, expectedAave, 1e16); // 1% tolerance
        assertApproxEqRel(morphoBalance, expectedMorpho, 1e16);

        console.log("Strategy allocation working correctly");
        console.log("Expected Aave:", expectedAave, "Actual:", aaveBalance);
        console.log("Expected Morpho:", expectedMorpho, "Actual:", morphoBalance);

        // Test strategy update
        allocations[0] = 5000; // 50% Aave
        allocations[1] = 5000; // 50% Morpho

        pilot.setPilotStrategy(adapters, allocations);

        (, uint256[] memory newAllocations) = pilot.getStrategy();
        assertEq(newAllocations[0], 5000);
        assertEq(newAllocations[1], 5000);

        console.log("Strategy updated successfully");
    }

    function test_Integration_AdapterInteraction() public {
        console.log("=== Testing Adapter Interactions ===");

        uint256 depositAmount = 1000e18;

        // Test Aave Adapter
        idrx.approve(address(aaveAdapter), depositAmount);
        uint256 aaveShares = aaveAdapter.deposit(depositAmount);

        uint256 aaveBalance = aaveAdapter.getBalance();
        assertGt(aaveBalance, 0);
        console.log("AaveAdapter deposit successful, balance:", aaveBalance);

        // Test conversion functions
        uint256 convertedShares = aaveAdapter.convertToShares(depositAmount);
        uint256 convertedAssets = aaveAdapter.convertToAssets(aaveShares);

        console.log("Converted shares:", convertedShares);
        console.log("Converted assets:", convertedAssets);

        // Test Morpho Adapter
        idrx.approve(address(morphoAdapter), depositAmount);
        uint256 morphoShares = morphoAdapter.deposit(depositAmount);

        uint256 morphoBalance = morphoAdapter.getBalance();
        assertGt(morphoBalance, 0);
        console.log("MorphoAdapter deposit successful, balance:", morphoBalance);

        // Test withdrawals
        uint256 withdrawnAave = aaveAdapter.withdraw(aaveShares);
        uint256 withdrawnMorpho = morphoAdapter.withdraw(morphoShares);

        assertGt(withdrawnAave, 0);
        assertGt(withdrawnMorpho, 0);

        console.log("Withdrawals successful");
        console.log("Withdrawn from Aave:", withdrawnAave);
        console.log("Withdrawn from Morpho:", withdrawnMorpho);
    }

    function test_Integration_ErrorHandling() public {
        console.log("=== Testing Error Handling ===");

        // Test SuperCluster errors
        vm.startPrank(user1);

        // Should fail: Zero amount
        vm.expectRevert();
        superCluster.deposit(address(pilot), address(idrx), 0);

        // Should fail: Unsupported token
        MockIDRX unsupportedToken = new MockIDRX();
        vm.expectRevert();
        superCluster.deposit(address(pilot), address(unsupportedToken), 1000e18);

        vm.stopPrank();

        // Test Adapter errors
        vm.expectRevert();
        aaveAdapter.deposit(0);

        vm.expectRevert();
        aaveAdapter.withdraw(1000e18); // No balance

        // Test Pilot errors
        address[] memory adapters = new address[](1);
        uint256[] memory allocations = new uint256[](1);
        adapters[0] = address(aaveAdapter);
        allocations[0] = 5000; // Invalid: not 100%

        vm.expectRevert();
        pilot.setPilotStrategy(adapters, allocations);

        console.log("Error handling tests passed");
    }

    function test_MultipleUsers_WrapUnwrap_WithRebaseYield() public {
        console.log("=== Testing Multiple Users Wrap/Unwrap with Rebasing Yield ===");

        uint256 depositAmount1 = 1000e18;
        uint256 depositAmount2 = 2000e18;

        // User 1 deposits and wraps
        vm.startPrank(user1);
        idrx.approve(address(superCluster), depositAmount1);
        superCluster.deposit(address(pilot), address(idrx), depositAmount1);
        sToken.approve(address(wsToken), depositAmount1);
        wsToken.wrap(depositAmount1);
        uint256 wsTokenBalance1 = wsToken.balanceOf(user1);
        assertEq(wsTokenBalance1, depositAmount1, "User1 wsToken balance should be 1:1");
        assertEq(sToken.balanceOf(user1), 0, "User1 sToken should be zero after wrap");
        vm.stopPrank();

        // User 2 deposits and wraps
        vm.startPrank(user2);
        idrx.approve(address(superCluster), depositAmount2);
        superCluster.deposit(address(pilot), address(idrx), depositAmount2);
        sToken.approve(address(wsToken), depositAmount2);
        wsToken.wrap(depositAmount2);
        uint256 wsTokenBalance2 = wsToken.balanceOf(user2);
        assertEq(wsTokenBalance2, depositAmount2, "User2 wsToken balance should be 1:1");
        assertEq(sToken.balanceOf(user2), 0, "User2 sToken should be zero after wrap");
        vm.stopPrank();

        // Simulate yield: add yield to pilot and rebase
        idrx.mint(address(pilot), 300e18); // 10% yield for both users
        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();

        // After rebase, wsToken contract's sToken balance should increase
        uint256 sTokenInWsToken = sToken.balanceOf(address(wsToken));
        assertGt(
            sTokenInWsToken, depositAmount1 + depositAmount2, "sToken in wsToken contract should increase after yield"
        );
        console.log("sToken in wsToken contract after rebase:", sTokenInWsToken);

        uint256 wsPerSt = wsToken.wsTokenPerStToken();
        console.log("Price 1 sToken in wsToken (1e18):", wsPerSt);

        // User 1 unwraps
        vm.startPrank(user1);
        wsToken.unwrap(wsTokenBalance1);
        uint256 sTokenAfterUnwrap1 = sToken.balanceOf(user1);
        assertGt(sTokenAfterUnwrap1, depositAmount1, "User1 should receive more sToken after unwrap due to yield");
        assertEq(wsToken.balanceOf(user1), 0, "User1 wsToken should be zero after unwrap");
        vm.stopPrank();

        // User 2 unwraps
        vm.startPrank(user2);
        wsToken.unwrap(wsTokenBalance2);
        uint256 sTokenAfterUnwrap2 = sToken.balanceOf(user2);
        assertGt(sTokenAfterUnwrap2, depositAmount2, "User2 should receive more sToken after unwrap due to yield");
        assertEq(wsToken.balanceOf(user2), 0, "User2 wsToken should be zero after unwrap");
        vm.stopPrank();

        // Proportionality check
        uint256 expectedRatio = (depositAmount2 * 1e18) / depositAmount1;
        uint256 actualRatio = (sTokenAfterUnwrap2 * 1e18) / sTokenAfterUnwrap1;
        assertApproxEqRel(actualRatio, expectedRatio, 1e16); // 1% tolerance

        console.log("User1 sToken after unwrap:", sTokenAfterUnwrap1);
        console.log("User2 sToken after unwrap:", sTokenAfterUnwrap2);

        vm.startPrank(user1);
        console.log("Balance before withdraw:", idrx.balanceOf(user1));

        superCluster.withdraw(address(idrx), sTokenAfterUnwrap1);
        vm.stopPrank();

        vm.warp(1 days);
        uint256 balanceIdrxBeforeWithdraw = idrx.balanceOf(user1);
        console.log("Balance idx user before withdraw:", balanceIdrxBeforeWithdraw);
        vm.prank(owner);
        Withdraw withdrawManager = Withdraw(superCluster.withdrawManager());
        idrx.transfer(address(withdrawManager), sTokenAfterUnwrap1);

        console.log("Balance manager transfer", idrx.balanceOf(address(withdrawManager)));
        console.log("Widraw Manager amount:", sTokenAfterUnwrap1);
        uint256 requestId = withdrawManager.nextRequestId() - 1;
        superCluster.finalizeWithdraw(requestId, sTokenAfterUnwrap1);
        superCluster.claim(requestId);

        uint256 sTokenAfterWithdraw1 = sToken.balanceOf(user1);
        console.log("User1 sToken after withdraw:", sTokenAfterWithdraw1);
        assertEq(sTokenAfterWithdraw1, 0, "User1 sToken should be zero after withdraw");

        uint256 balanceIdrxAfterWithdraw = idrx.balanceOf(user1);
        uint256 idrxAfterWithdraw1 = balanceIdrxAfterWithdraw - balanceIdrxBeforeWithdraw;
        console.log("User1 IDRX after withdraw:", idrxAfterWithdraw1);
        assertApproxEqRel(
            idrxAfterWithdraw1,
            sTokenAfterUnwrap1,
            1e16,
            "User1 should receive IDRX equal to sToken withdrawn (including yield)"
        );

        vm.startPrank(user2);
        console.log("Balance before withdraw:", idrx.balanceOf(user2));

        superCluster.withdraw(address(idrx), sTokenAfterUnwrap2);
        vm.stopPrank();

        vm.warp(1 days);
        uint256 balanceIdrxBeforeWithdraw2 = idrx.balanceOf(user2);
        console.log("Balance idx user before withdraw:", balanceIdrxBeforeWithdraw2);
        vm.prank(owner);
        idrx.transfer(address(withdrawManager), sTokenAfterUnwrap2);

        console.log("Balance manager transfer", idrx.balanceOf(address(withdrawManager)));
        console.log("Widraw Manager amount:", sTokenAfterUnwrap2);
        requestId = withdrawManager.nextRequestId() - 1;
        superCluster.finalizeWithdraw(requestId, sTokenAfterUnwrap2);
        superCluster.claim(requestId);

        uint256 sTokenAfterWithdraw2 = sToken.balanceOf(user2);
        console.log("User1 sToken after withdraw:", sTokenAfterWithdraw2);
        assertEq(sTokenAfterWithdraw2, 0, "User1 sToken should be zero after withdraw");

        uint256 balanceIdrxAfterWithdraw2 = idrx.balanceOf(user2);
        uint256 idrxAfterWithdraw2 = balanceIdrxAfterWithdraw2 - balanceIdrxBeforeWithdraw2;
        console.log("User1 IDRX after withdraw:", idrxAfterWithdraw2);
        assertApproxEqRel(
            idrxAfterWithdraw2,
            sTokenAfterUnwrap2,
            1e16,
            "User1 should receive IDRX equal to sToken withdrawn (including yield)"
        );

        console.log("Multiple users wrap/unwrap with rebasing yield test complete");
    }
}
