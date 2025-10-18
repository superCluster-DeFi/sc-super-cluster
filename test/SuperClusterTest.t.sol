// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SuperCluster} from "../src/SuperCluster.sol";
import {SToken} from "../src/tokens/SToken.sol";
import {WsToken} from "../src/tokens/WsToken.sol";
import {Pilot} from "../src/pilot/Pilot.sol";
import {AaveAdapter} from "../src/adapter/AaveAdapter.sol";
import {MorphoAdapter} from "../src/adapter/MorphoAdapter.sol";
import {LendingPool} from "../src/mocks/MockAave.sol";
import {MockMorpho} from "../src/mocks/MockMorpho.sol";
import {MockIDRX} from "../src/mocks/tokens/MockIDRX.sol";
import {Id, MarketParams} from "../src/mocks/interfaces/IMorpho.sol";
import {Withdraw} from "../src/tokens/WithDraw.sol";
import {IAdapter} from "../src/interfaces/IAdapter.sol";

contract SuperClusterTest is Test {
    SuperCluster public superCluster;
    SToken public sToken;
    WsToken public wsToken;
    MockIDRX public idrx;
    Pilot public pilot;
    AaveAdapter public aaveAdapter;
    MorphoAdapter public morphoAdapter;
    LendingPool public mockAave;
    MockMorpho public mockMorpho;
    Withdraw public withdrawManager;

    address public owner;
    address public user1;
    address public user2;

    uint256 constant INITIAL_SUPPLY = 1000000e18;
    uint256 constant DEPOSIT_AMOUNT = 1000e18;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        idrx = new MockIDRX();
        idrx.mint(owner, INITIAL_SUPPLY);
        idrx.mint(user1, INITIAL_SUPPLY);
        idrx.mint(user2, INITIAL_SUPPLY);

        // Deploy SToken, WsToken and Withdraw separately to avoid large SuperCluster initcode
        sToken = new SToken("sMockIDRX", "sIDRX", address(idrx));
        wsToken = new WsToken("wsMockIDRX", "wsIDRX", address(sToken));

        // Deploy SuperCluster first with a placeholder withdraw manager (address(0))
        superCluster = new SuperCluster(address(idrx), address(sToken), address(wsToken), address(0));

        // Deploy Withdraw manager with the correct SuperCluster address
        withdrawManager = new Withdraw(address(sToken), address(idrx), address(superCluster), 1 days);

        // Set the withdraw manager in SuperCluster (owner only)
        superCluster.setWithdrawManager(address(withdrawManager));

        // After deploying SuperCluster, set proper owner/links as needed
        // Set authorized minter flags on tokens for SuperCluster
        sToken.setAuthorizedMinter(address(superCluster), true);
        wsToken.setAuthorizedMinter(address(superCluster), true);

        // Update withdrawManager's superCluster reference if necessary (owner only)
        // withdrawManager was created with zero superCluster, so transfer ownership to this test and set if needed

        //Deploy Mock protocols
        _deployMockProtocols();

        // Deploy adapters
        _deployAdapters();

        // Deploy pilot
        _deployPilot();

        // Setup pilot strategy
        _setupPilotStrategy();

        // Register pilot
        superCluster.registerPilot(address(pilot), address(idrx));

        // (Opsional) log untuk debugging
        console.log("SuperCluster:", address(superCluster));
        console.log("SToken:", address(sToken));
        console.log("Withdraw:", address(withdrawManager));
    }

    function _deployMockProtocols() internal {
        // Deploy MockAave
        address mockOracle = address(0x1);
        uint256 ltv = 800000000000000000; // 80% LTV

        mockAave = new LendingPool(address(idrx), address(idrx), mockOracle, ltv);

        // Deploy MockMorpho
        mockMorpho = new MockMorpho();

        // Setup MockMorpho
        address mockIrm = address(0x2);
        uint256 lltv = 800000000000000000;

        mockMorpho.enableIrm(mockIrm);
        mockMorpho.enableLltv(lltv);

        // Create Morpho market
        MarketParams memory params = MarketParams({
            loanToken: address(idrx),
            collateralToken: address(idrx),
            oracle: mockOracle,
            irm: mockIrm,
            lltv: lltv
        });

        mockMorpho.createMarket(params);
    }

    function _deployAdapters() internal {
        // Deploy AaveAdapter
        aaveAdapter = new AaveAdapter(address(idrx), address(mockAave), "Aave V3", "Conservative Lending");

        // Deploy MorphoAdapter
        MarketParams memory params = MarketParams({
            loanToken: address(idrx),
            collateralToken: address(idrx),
            oracle: address(0x1),
            irm: address(0x2),
            lltv: 800000000000000000
        });

        morphoAdapter =
            new MorphoAdapter(address(idrx), address(mockMorpho), params, "Morpho Blue", "High Yield Lending");
    }

    function _deployPilot() internal {
        // First deploy adapters so we can set up the pilot with them
        aaveAdapter = new AaveAdapter(address(idrx), address(mockAave), "Aave V3", "Conservative Lending");

        pilot = new Pilot(
            "Conservative DeFi Pilot",
            "Low-risk DeFi strategies focusing on lending protocols",
            address(idrx),
            address(idrx),
            address(mockAave),
            address(superCluster)
        );
    }

    function _setupPilotStrategy() internal {
        // Register the pilot's strategy
        string memory strategyName = "Conservative DeFi Pilot";
        superCluster.registerStrategy(strategyName, address(pilot));

        // Setup test users
        vm.startPrank(user1);
        superCluster.selectStrategy(strategyName);
        idrx.approve(address(superCluster), type(uint256).max);
        // Also approve pilot directly for investment operations
        idrx.approve(address(pilot), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        superCluster.selectStrategy(strategyName);
        idrx.approve(address(superCluster), type(uint256).max);
        idrx.approve(address(pilot), type(uint256).max);
        vm.stopPrank();

        // Make sure pilot has approval for IDRX operations
        vm.startPrank(owner);
        idrx.approve(address(pilot), type(uint256).max);
        // Make sure withdrawManager is properly set up
        withdrawManager = superCluster.withdrawManager();
        vm.stopPrank();
    }

    // ==================== SUPERCLUSTER TESTS ====================

    function test_SuperCluster_Deploy() public view {
        assertEq(sToken.name(), "sMockIDRX");
        assertEq(wsToken.name(), "wsMockIDRX");
        assertTrue(superCluster.supportedTokens(address(idrx)));
        assertEq(superCluster.owner(), owner);
    }

    function test_SuperCluster_Deposit() public {
        string memory strategyName = "Conservative DeFi Pilot";

        vm.startPrank(user1);
        idrx.approve(address(superCluster), type(uint256).max);
        superCluster.selectStrategy(strategyName);

        uint256 balanceBefore = sToken.balanceOf(user1);
        console.log("sToken balance before deposit:", balanceBefore);

        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);

        uint256 balanceAfter = sToken.balanceOf(user1);
        console.log("sToken balance after deposit:", balanceAfter);

        assertEq(balanceAfter - balanceBefore, DEPOSIT_AMOUNT);
        assertEq(superCluster.tokenBalances(address(idrx)), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_SuperCluster_Withdraw() public {
        string memory strategyName = "Conservative DeFi Pilot";

        vm.startPrank(user1);
        idrx.approve(address(superCluster), type(uint256).max);
        superCluster.selectStrategy(strategyName);

        // Initial deposit
        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);
        uint256 sTokenBalance = sToken.balanceOf(user1);
        assertEq(sTokenBalance, DEPOSIT_AMOUNT, "Should receive sToken for deposit");

        // Wait for lock period
        vm.warp(block.timestamp + 4 days);

        // Withdraw full amount
        superCluster.withdraw(address(idrx), DEPOSIT_AMOUNT);

        // Check balances after withdrawal
        uint256 sTokenBalanceAfter = sToken.balanceOf(user1);
        uint256 withdrawManagerBalance = sToken.balanceOf(address(superCluster.withdrawManager()));

        assertEq(sTokenBalanceAfter, 0, "User should have no sToken left");
        assertEq(withdrawManagerBalance, DEPOSIT_AMOUNT, "WithdrawManager should hold sToken");
        vm.stopPrank();
    }

    function test_SuperCluster_SelectPilot() public {
        string memory strategyName = "Conservative DeFi Pilot";

        // First deposit
        vm.startPrank(user1);
        idrx.approve(address(superCluster), type(uint256).max);
        superCluster.selectStrategy(strategyName);
        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);

        uint256 pilotBalanceBefore = idrx.balanceOf(address(pilot));
        console.log("Pilot balance before:", pilotBalanceBefore);

        // Select pilot
        superCluster.selectPilot(address(pilot), address(idrx), DEPOSIT_AMOUNT);

        uint256 pilotBalanceAfter = idrx.balanceOf(address(pilot));

        vm.stopPrank();
        assertEq(pilotBalanceAfter - pilotBalanceBefore, DEPOSIT_AMOUNT);
    }

    function test_SuperCluster_RegisterPilot() public {
        address newPilot = makeAddr("newPilot");

        superCluster.registerPilot(newPilot, address(idrx));

        assertTrue(superCluster.registeredPilots(newPilot));
        address[] memory pilots = superCluster.getPilots();
        bool found = false;
        for (uint256 i = 0; i < pilots.length; i++) {
            if (pilots[i] == newPilot) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_SuperCluster_Rebase() public {
        string memory strategyName = "Conservative DeFi Pilot";

        // Deposit to SuperCluster
        vm.startPrank(user1);
        idrx.approve(address(superCluster), type(uint256).max);
        superCluster.selectStrategy(strategyName);
        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 aumBefore = superCluster.calculateTotalAUM();

        vm.warp(block.timestamp + 1 days);
        // Trigger rebase
        superCluster.rebase();

        uint256 aumAfter = sToken.totalAssetsUnderManagement();
        assertEq(aumAfter, aumBefore);
    }

    function test_Fail_SuperCluster_Deposit_Zero_Amount() public {
        vm.prank(user1);
        vm.expectRevert();
        superCluster.deposit(address(idrx), 0);
    }

    function test_Fail_SuperCluster_Deposit_Unsupported_Token() public {
        MockIDRX unsupportedToken = new MockIDRX();
        vm.prank(user1);
        vm.expectRevert();
        superCluster.deposit(address(unsupportedToken), DEPOSIT_AMOUNT);
    }

    // ==================== STOKEN TESTS ====================

    function test_SToken_InitialState() public view {
        assertEq(sToken.name(), "sMockIDRX");
        assertEq(sToken.symbol(), "sIDRX");
        assertEq(sToken.decimals(), 18);
        assertEq(sToken.totalSupply(), 0);
    }

    function test_Fail_SToken_UnauthorizedMint() public {
        vm.prank(user1);
        vm.expectRevert("Unauthorized");
        sToken.mint(user1, 1000e18);
    }

    // ==================== PILOT TESTS ====================

    function test_Pilot_InitialState() public view {
        assertEq(pilot.name(), "Conservative DeFi Pilot");
        assertTrue(bytes(pilot.description()).length > 0);
        assertEq(pilot.TOKEN(), address(idrx));
    }

    function test_Pilot_GetStrategy() public view {
        // Strategy is fixed in constructor, verify it's properly set
        (address[] memory returnedAdapters, uint256[] memory returnedAllocations) = pilot.getStrategy();
        IAdapter localAaveAdapter = pilot.aaveAdapter();

        assertEq(returnedAdapters.length, 1);
        assertEq(returnedAdapters[0], address(localAaveAdapter)); // Use the adapter from pilot
        assertEq(returnedAllocations.length, 1);
        assertEq(returnedAllocations[0], 10000); // Should be 100%
    }

    function test_Pilot_Invest() public {
        // Get the pilot's fixed strategy
        (address[] memory adapters, uint256[] memory allocations) = pilot.getStrategy();
        IAdapter aave = pilot.aaveAdapter();

        // Fund pilot with tokens
        idrx.transfer(address(pilot), DEPOSIT_AMOUNT);

        // Invest using pilot's fixed strategy
        pilot.invest(DEPOSIT_AMOUNT, adapters, allocations);

        // Check if pilot's adapter received tokens
        assertTrue(aave.getBalance() > 0);
    }

    function test_Pilot_GetTotalValue() public {
        // Get the pilot's fixed strategy
        (address[] memory adapters, uint256[] memory allocations) = pilot.getStrategy();

        // Fund pilot with tokens and invest them
        idrx.transfer(address(pilot), 500e18);
        idrx.approve(address(pilot), 500e18);
        pilot.invest(500e18, adapters, allocations);

        uint256 totalValue = pilot.getTotalValue();

        // Should include invested funds
        assertGt(totalValue, 0);
    }

    function test_Fail_Pilot_InvalidAllocation() public {
        address[] memory adapters = new address[](1);
        uint256[] memory allocations = new uint256[](1);

        adapters[0] = address(aaveAdapter);
        allocations[0] = 5000; // Only 50%, should fail

        vm.expectRevert();
        pilot.setPilotStrategy(adapters, allocations);
    }

    // ==================== AAVE ADAPTER TESTS ====================

    function test_AaveAdapter_InitialState() public view {
        assertEq(aaveAdapter.getProtocolName(), "Aave V3");
        assertEq(aaveAdapter.getPilotStrategy(), "Conservative Lending");
        assertEq(address(aaveAdapter.LENDINGPOOL()), address(mockAave));
        assertTrue(aaveAdapter.isActive());
    }

    function test_AaveAdapter_Deposit() public {
        uint256 depositAmount = 1000e18;

        idrx.approve(address(aaveAdapter), depositAmount);

        uint256 shares = aaveAdapter.deposit(depositAmount);

        assertGt(shares, 0);
        assertGt(aaveAdapter.getBalance(), 0);
        assertEq(aaveAdapter.totalDeposited(), depositAmount);
    }

    function test_AaveAdapter_Withdraw() public {
        uint256 depositAmount = 1000e18;

        // First deposit
        idrx.approve(address(aaveAdapter), depositAmount);
        uint256 shares = aaveAdapter.deposit(depositAmount);

        uint256 balanceBefore = idrx.balanceOf(address(this));

        // Withdraw
        uint256 withdrawn = aaveAdapter.withdraw(shares);

        uint256 balanceAfter = idrx.balanceOf(address(this));

        assertGt(withdrawn, 0);
        assertGt(balanceAfter, balanceBefore);
    }

    function test_AaveAdapter_ConvertToShares() public view {
        uint256 assets = 1000e18;
        uint256 shares = aaveAdapter.convertToShares(assets);

        // Should be 1:1 initially
        assertEq(shares, assets);
    }

    function test_Fail_AaveAdapter_DepositZero() public {
        idrx.approve(address(aaveAdapter), 0);
        vm.expectRevert();
        aaveAdapter.deposit(0);
    }

    function test_Fail_AaveAdapter_WithdrawExcessive() public {
        idrx.approve(address(aaveAdapter), 0);
        vm.expectRevert();
        aaveAdapter.withdraw(1000e18); // No deposits made
    }

    // ==================== MORPHO ADAPTER TESTS ====================

    function test_MorphoAdapter_InitialState() public view {
        assertEq(morphoAdapter.getProtocolName(), "Morpho Blue");
        assertEq(morphoAdapter.getPilotStrategy(), "High Yield Lending");
        assertTrue(morphoAdapter.isActive());
        assertTrue(morphoAdapter.getMarketId() != bytes32(0));
    }

    function test_MorphoAdapter_Deposit() public {
        uint256 depositAmount = 1000e18;

        idrx.approve(address(morphoAdapter), depositAmount);

        uint256 shares = morphoAdapter.deposit(depositAmount);

        assertGt(shares, 0);
        assertGt(morphoAdapter.getBalance(), 0);
        assertEq(morphoAdapter.totalDeposited(), depositAmount);
    }

    function test_MorphoAdapter_Withdraw() public {
        uint256 depositAmount = 1000e18;

        // First deposit
        idrx.approve(address(morphoAdapter), depositAmount);
        uint256 shares = morphoAdapter.deposit(depositAmount);

        uint256 balanceBefore = idrx.balanceOf(address(this));

        // Withdraw
        uint256 withdrawn = morphoAdapter.withdraw(shares);

        uint256 balanceAfter = idrx.balanceOf(address(this));

        assertGt(withdrawn, 0);
        assertGt(balanceAfter, balanceBefore);
    }

    function test_MorphoAdapter_GetPosition() public {
        uint256 depositAmount = 1000e18;

        idrx.approve(address(morphoAdapter), depositAmount);
        morphoAdapter.deposit(depositAmount);

        (uint128 supplyShares, uint128 borrowShares, uint128 collateral) = morphoAdapter.getPosition();

        assertGt(supplyShares, 0);
        assertEq(borrowShares, 0); // No borrowing
        assertEq(collateral, 0);
    }

    function test_Fail_MorphoAdapter_DepositZero() public {
        idrx.approve(address(morphoAdapter), 0);
        vm.expectRevert();
        morphoAdapter.deposit(0);
    }
}
