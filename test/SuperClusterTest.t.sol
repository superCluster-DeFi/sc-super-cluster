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

        superCluster = new SuperCluster(address(idrx), address(0));

        sToken = superCluster.underlyingToken();
        wsToken = superCluster.wsToken();

        Withdraw withdrawManager = new Withdraw(address(sToken), address(idrx), address(superCluster), 1 days);

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
        pilot = new Pilot(
            "Conservative DeFi Pilot", "Low-risk DeFi strategies focusing on lending protocols", address(idrx)
        );
    }

    function _setupPilotStrategy() internal {
        address[] memory adapters = new address[](2);
        uint256[] memory allocations = new uint256[](2);

        adapters[0] = address(aaveAdapter);
        adapters[1] = address(morphoAdapter);
        allocations[0] = 6000; // 60% Aave
        allocations[1] = 4000; // 40% Morpho

        pilot.setPilotStrategy(adapters, allocations);
    }

    // ==================== SUPERCLUSTER TESTS ====================

    function test_SuperCluster_Deploy() public view {
        assertEq(sToken.name(), "sMockIDRX");
        assertEq(wsToken.name(), "Wrapped sIDRX");
        assertEq(sToken.symbol(), "sIDRX");
        assertEq(wsToken.symbol(), "wsIDRX");
        assertTrue(superCluster.supportedTokens(address(idrx)));
        assertEq(superCluster.owner(), owner);
    }

    function test_SuperCluster_Deposit() public {
        vm.startPrank(user1);
        idrx.approve(address(superCluster), DEPOSIT_AMOUNT);

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
        // First deposit
        vm.startPrank(user1);
        idrx.approve(address(superCluster), DEPOSIT_AMOUNT);
        superCluster.deposit(address(idrx), DEPOSIT_AMOUNT);

        uint256 idrxBalanceBefore = idrx.balanceOf(user1);
        uint256 sTokenBalanceBefore = sToken.balanceOf(user1);

        // Withdraw
        superCluster.withdraw(address(idrx), DEPOSIT_AMOUNT);

        uint256 idrxBalanceAfter = idrx.balanceOf(user1);
        uint256 sTokenBalanceAfter = sToken.balanceOf(user1);

        console.log("Requested withdraw amount:", DEPOSIT_AMOUNT);

        assertEq(idrxBalanceAfter - idrxBalanceBefore, DEPOSIT_AMOUNT);
        assertEq(sTokenBalanceBefore - sTokenBalanceAfter, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_SuperCluster_SelectPilot() public {
        // First deposit
        vm.startPrank(user1);
        idrx.approve(address(superCluster), DEPOSIT_AMOUNT);
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
        // Deposit to SuperCluster
        vm.startPrank(user1);
        idrx.approve(address(superCluster), DEPOSIT_AMOUNT);
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

    function test_Pilot_SetStrategy() public {
        address[] memory adapters = new address[](1);
        uint256[] memory allocations = new uint256[](1);

        adapters[0] = address(aaveAdapter);
        allocations[0] = 10000; // 100%

        pilot.setPilotStrategy(adapters, allocations);

        (address[] memory returnedAdapters, uint256[] memory returnedAllocations) = pilot.getStrategy();

        assertEq(returnedAdapters.length, 1);
        assertEq(returnedAllocations.length, 1);
        assertEq(returnedAdapters[0], address(aaveAdapter));
        assertEq(returnedAllocations[0], 10000);
    }

    function test_Pilot_Invest() public {
        // Transfer tokens to pilot
        idrx.transfer(address(pilot), DEPOSIT_AMOUNT);

        address[] memory adapters = new address[](1);
        uint256[] memory allocations = new uint256[](1);
        adapters[0] = address(aaveAdapter);
        allocations[0] = 10000;

        // Fund adapter with tokens first
        idrx.transfer(address(aaveAdapter), DEPOSIT_AMOUNT);

        pilot.invest(DEPOSIT_AMOUNT, adapters, allocations);

        // Check if adapter received tokens
        assertTrue(aaveAdapter.getBalance() > 0);
    }

    function test_Pilot_GetTotalValue() public {
        // Transfer some tokens to pilot (idle funds)
        idrx.transfer(address(pilot), 500e18);

        uint256 totalValue = pilot.getTotalValue();

        // Should include idle funds
        assertGe(totalValue, 500e18);
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
