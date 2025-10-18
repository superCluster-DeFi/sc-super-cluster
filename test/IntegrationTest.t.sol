// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SuperClusterTest.t.sol";

contract IntegrationTest is SuperClusterTest {
    function test_Integration_FullUserFlow() public {
        console.log("=== Testing Full User Flow ===");

        // 1. User deposits to SuperCluster
        vm.startPrank(user1);
        idrx.approve(address(superCluster), DEPOSIT_AMOUNT);
        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);

        uint256 sTokenBalance = sToken.balanceOf(user1);
        assertEq(sTokenBalance, DEPOSIT_AMOUNT);
        console.log("User deposited and received sTokens");

        // 2. User selects pilot
        superCluster.selectPilot(address(pilot), address(idrx), DEPOSIT_AMOUNT);

        uint256 pilotBalance = idrx.balanceOf(address(pilot));
        assertEq(pilotBalance, DEPOSIT_AMOUNT);
        console.log("User selected pilot, funds transferred");

        vm.stopPrank();

        // 3. Pilot auto-invests using strategy
        address[] memory adapters = new address[](2);
        uint256[] memory allocations = new uint256[](2);
        adapters[0] = address(aaveAdapter);
        adapters[1] = address(morphoAdapter);
        allocations[0] = 6000; // 60%
        allocations[1] = 4000; // 40%

        pilot.invest(DEPOSIT_AMOUNT, adapters, allocations);

        // Check adapter balances
        uint256 aaveBalance = aaveAdapter.getBalance();
        uint256 morphoBalance = morphoAdapter.getBalance();

        assertGt(aaveBalance, 0);
        assertGt(morphoBalance, 0);
        console.log("Pilot invested in adapters");
        console.log("Aave balance:", aaveBalance);
        console.log("Morpho balance:", morphoBalance);

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

        // User 1 deposits
        vm.startPrank(user1);
        idrx.approve(address(superCluster), depositAmount1);
        superCluster.deposit(address(idrx), depositAmount1);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        idrx.approve(address(superCluster), depositAmount2);
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

        // Set up initial strategy
        address[] memory adapters = new address[](2);
        uint256[] memory allocations = new uint256[](2);
        adapters[0] = address(aaveAdapter);
        adapters[1] = address(morphoAdapter);
        allocations[0] = 7000; // 70% Aave
        allocations[1] = 3000; // 30% Morpho

        pilot.setPilotStrategy(adapters, allocations);

        // Transfer funds to pilot
        idrx.transfer(address(pilot), DEPOSIT_AMOUNT);

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

        (address[] memory newAdapters, uint256[] memory newAllocations) = pilot.getStrategy();
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
