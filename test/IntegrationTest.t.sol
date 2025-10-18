// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SuperClusterTest.t.sol";

contract IntegrationTest is SuperClusterTest {
    function test_Integration_FullUserFlow() public {
        console.log("=== Testing Full User Flow ===");

        // Set up approvals
        vm.startPrank(user1);
        idrx.approve(address(superCluster), type(uint256).max); // Max approve for all operations

        // 1. User deposits to SuperCluster
        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);

        uint256 sTokenBalance = sToken.balanceOf(user1);
        assertEq(sTokenBalance, DEPOSIT_AMOUNT);
        console.log("User deposited and received sTokens");

        // Set strategy first
        string memory strategyName = "Conservative DeFi Pilot";
        superCluster.selectStrategy(strategyName);

        // 2. User selects pilot
        superCluster.selectPilot(address(pilot), address(idrx), DEPOSIT_AMOUNT);

        uint256 pilotBalance = idrx.balanceOf(address(pilot));
        assertEq(pilotBalance, DEPOSIT_AMOUNT);
        console.log("User selected pilot, funds transferred");

        vm.stopPrank();

        // 3. Pilot auto-invests using strategy
        (address[] memory adapters, uint256[] memory allocations) = pilot.getStrategy();
        IAdapter pilotAaveAdapter = pilot.aaveAdapter();

        pilot.invest(DEPOSIT_AMOUNT, adapters, allocations);

        // Check adapter balance
        uint256 aaveBalance = pilotAaveAdapter.getBalance();

        assertGt(aaveBalance, 0);
        console.log("Pilot invested using its adapter");
        console.log("Adapter balance:", aaveBalance);

        // 4. Check total AUM calculation
        uint256 totalAUM = superCluster.calculateTotalAUM();
        assertGt(totalAUM, 0);
        console.log("Total AUM calculated:", totalAUM);

        // 5. Trigger rebase
        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();
        console.log("Rebase completed");

        // 6. Simulate yield and rebase again
        // Add some yield to adapters (simulate protocol earnings)
        idrx.mint(address(mockAave), 100e18); // 10% yield on Aave
        idrx.mint(address(mockMorpho), 50e18); // 5% yield on Morpho

        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();

        // User's sToken balance should increase due to rebase
        uint256 newSTokenBalance = sToken.balanceOf(user1);
        console.log("After yield - sToken balance:", newSTokenBalance);

        console.log("=== Full Integration Test Complete ===");
    }

    function test_Integration_MultipleUsers() public {
        console.log("=== Testing Multiple Users ===");

        uint256 depositAmount1 = 1000e18;
        uint256 depositAmount2 = 2000e18;
        string memory strategyName = "Conservative DeFi Pilot";

        // User 1 deposits
        vm.startPrank(user1);
        idrx.approve(address(superCluster), type(uint256).max);
        superCluster.selectStrategy(strategyName);
        superCluster.deposit(address(idrx), depositAmount1);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        idrx.approve(address(superCluster), type(uint256).max);
        superCluster.selectStrategy(strategyName);
        superCluster.deposit(address(idrx), depositAmount2);
        vm.stopPrank();

        // Check proportional sToken balances
        uint256 balance1 = sToken.balanceOf(user1);
        uint256 balance2 = sToken.balanceOf(user2);

        assertEq(balance1, depositAmount1);
        assertEq(balance2, depositAmount2);

        // Trigger rebase with yield
        uint256 totalSupply = sToken.totalSupply();
        uint256 newAUM = totalSupply + (totalSupply * 10 / 100); // 10% yield

        vm.warp(block.timestamp + 1 days);
        superCluster.rebaseWithAUM(newAUM);

        // Check new balances (should increase proportionally)
        uint256 newBalance1 = sToken.balanceOf(user1);
        uint256 newBalance2 = sToken.balanceOf(user2);

        assertGt(newBalance1, balance1);
        assertGt(newBalance2, balance2);

        // Ratio should be maintained
        assertApproxEqRel(newBalance2, newBalance1 * 2, 1e16); // 1% tolerance

        console.log("Multiple users test complete");
        console.log("User1 balance after yield:", newBalance1);
        console.log("User2 balance after yield:", newBalance2);
    }

    function test_Integration_PilotStrategy() public {
        console.log("=== Testing Pilot Strategy Management ===");

        // Get pilot's fixed strategy
        (address[] memory adapters, uint256[] memory allocations) = pilot.getStrategy();
        IAdapter pilotAaveAdapter = pilot.aaveAdapter();

        // Transfer funds to pilot
        idrx.transfer(address(pilot), DEPOSIT_AMOUNT);

        // Invest using pilot's strategy
        pilot.invest(DEPOSIT_AMOUNT, adapters, allocations);

        // Check allocation
        uint256 aaveBalance = pilotAaveAdapter.getBalance();
        assertGt(aaveBalance, 0, "Should have balance in Aave adapter");

        console.log("Strategy allocation working correctly");
        console.log("Aave balance:", aaveBalance);

        // Verify strategy settings
        (address[] memory currentAdapters, uint256[] memory currentAllocations) = pilot.getStrategy();
        assertEq(currentAdapters.length, 1, "Should have single adapter");
        assertEq(currentAllocations.length, 1, "Should have single allocation");
        assertEq(currentAllocations[0], 10000, "Should be 100% allocated");
        assertEq(currentAdapters[0], address(pilotAaveAdapter), "Should match pilot's adapter");

        console.log("Strategy verification successful");
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
        superCluster.deposit(address(idrx), 0);

        // Should fail: Unsupported token
        MockIDRX unsupportedToken = new MockIDRX();
        vm.expectRevert();
        superCluster.deposit(address(unsupportedToken), 1000e18);

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
}
