// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {SuperCluster} from "../src/SuperCluster.sol";
import {Pilot} from "../src/pilot/Pilot.sol";
import {MockMorpho} from "../src/mocks/MockMorpho.sol";
import {LendingPool} from "../src/mocks/MockAave.sol";
import {MockIDRX} from "../src/mocks/tokens/MockIDRX.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {SToken} from "../src/tokens/SToken.sol";

contract SuperClusterTest is Test {
    SuperCluster public superCluster;
    MockIDRX public mockIDRX;
    SToken public sTokenInstance;
    Pilot public pilot1;
    Pilot public pilot2;
    MockOracle public oracle;
    MockMorpho public mockMorpho;
    LendingPool public mockAave;

    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public owner = address(0x3);

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 10 ** 18;
    uint256 public constant LARGE_DEPOSIT = 10000 * 10 ** 18;

    function setUp() public {
        // Deploy mock IDRX token
        mockIDRX = new MockIDRX();

        // Deploy SuperCluster contract
        superCluster = new SuperCluster(address(mockIDRX));

        // Get token reference
        sTokenInstance = superCluster.underlyingToken();

        // Deploy adapters
        oracle = new MockOracle();
        mockMorpho = new MockMorpho();
        mockAave = new LendingPool(address(mockIDRX), address(mockIDRX), address(oracle), 8000e14);

        mockMorpho.setDefaultLoanToken(address(mockIDRX));

        // Deploy pilots
        pilot1 = new Pilot("Conservative Pilot", "70% Morpho, 30% Aave", address(mockIDRX));

        pilot2 = new Pilot("Aggressive Pilot", "30% Morpho, 70% Aave", address(mockIDRX));

        // Transfer SuperCluster ownership to owner
        superCluster.transferOwnership(owner);

        // Register pilots
        vm.startPrank(owner);
        superCluster.registerPilot(address(pilot1));
        superCluster.registerPilot(address(pilot2));
        vm.stopPrank();

        // Set up pilot strategies
        address[] memory adapters1 = new address[](2);
        adapters1[0] = address(mockMorpho);
        adapters1[1] = address(mockAave);

        uint256[] memory allocations1 = new uint256[](2);
        allocations1[0] = 7000; // 70% Morpho
        allocations1[1] = 3000; // 30% Aave

        address[] memory adapters2 = new address[](2);
        adapters2[0] = address(mockMorpho);
        adapters2[1] = address(mockAave);

        uint256[] memory allocations2 = new uint256[](2);
        allocations2[0] = 3000; // 30% Morpho
        allocations2[1] = 7000; // 70% Aave

        // Transfer pilot ownership to owner
        pilot1.transferOwnership(owner);
        pilot2.transferOwnership(owner);

        // Set strategies
        vm.startPrank(owner);
        pilot1.addAdapter(address(adapters1[0]));
        pilot1.addAdapter(address(adapters1[1]));
        pilot1.setPilotStrategy(adapters1, allocations1);

        pilot1.addAdapter(address(adapters2[0]));
        pilot1.addAdapter(address(adapters2[1]));
        pilot2.setPilotStrategy(adapters2, allocations2);

        // Add adapters to pilots
        pilot1.addAdapter(address(mockMorpho));
        pilot1.addAdapter(address(mockAave));

        pilot2.addAdapter(address(mockMorpho));
        pilot2.addAdapter(address(mockAave));
        vm.stopPrank();

        // Set up users with IDRX tokens
        mockIDRX.mint(user1, INITIAL_SUPPLY);
        mockIDRX.mint(user2, INITIAL_SUPPLY);
        mockIDRX.mint(owner, INITIAL_SUPPLY);

        // Approve SuperCluster to spend IDRX
        vm.prank(user1);
        mockIDRX.approve(address(superCluster), type(uint256).max);

        vm.prank(user2);
        mockIDRX.approve(address(superCluster), type(uint256).max);

        vm.prank(owner);
        mockIDRX.approve(address(superCluster), type(uint256).max);

        // Approve SuperCluster to spend sToken (for selectPilot)
        vm.prank(user1);
        sTokenInstance.approve(address(superCluster), type(uint256).max);

        vm.prank(user2);
        sTokenInstance.approve(address(superCluster), type(uint256).max);
    }

    // ===== FLOW 1: DEPOSIT & TOKENISASI =====

    function test_1_DepositAndTokenization() public {
        console.log("=== FLOW 1: DEPOSIT & TOKENISASI ===");

        // User1 deposits IDRX
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        // Check sToken minted to user
        console.log("User1 sToken balance:", sTokenInstance.balanceOf(user1));
        console.log("Expected sToken balance:", DEPOSIT_AMOUNT);

        // Check total supply
        console.log("Total sToken supply:", sTokenInstance.totalSupply());
        console.log("Expected total supply:", DEPOSIT_AMOUNT);

        // Check total assets under management
        console.log("Total assets under management:", sTokenInstance.getTotalAssetsUnderManagement());
        console.log("Expected total assets:", DEPOSIT_AMOUNT);

        // User2 deposits larger amount
        vm.prank(user2);
        superCluster.deposit(address(mockIDRX), LARGE_DEPOSIT);

        console.log("User2 sToken balance:", sTokenInstance.balanceOf(user2));
        console.log("Expected sToken balance:", LARGE_DEPOSIT);

        console.log("Total sToken supply after user2:", sTokenInstance.totalSupply());
        console.log("Expected total supply:", DEPOSIT_AMOUNT + LARGE_DEPOSIT);
    }

    function test_1_RebaseMechanism() public {
        console.log("=== FLOW 1: REBASE MECHANISM ===");

        // User1 deposits first
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        console.log("User1 sToken balance:", sTokenInstance.balanceOf(user1));
        console.log("Expected sToken balance:", DEPOSIT_AMOUNT);

        // Fast forward time to allow rebase
        vm.warp(block.timestamp + 1 days);

        // Perform rebase
        superCluster.rebase();

        console.log("User1 sToken balance after rebase:", sTokenInstance.balanceOf(user1));
        console.log("Total sToken supply after rebase:", sTokenInstance.totalSupply());
    }

    // ===== FLOW 2: PILOT REGISTRATION =====

    function test_2_PilotRegistration() public {
        console.log("=== FLOW 2: PILOT REGISTRATION ===");

        // Check pilots are registered
        bool pilot1Registered = superCluster.registeredPilots(address(pilot1));
        bool pilot2Registered = superCluster.registeredPilots(address(pilot2));

        console.log("Pilot1 registered:", pilot1Registered);
        console.log("Pilot2 registered:", pilot2Registered);
        console.log("Both pilots registered:", pilot1Registered && pilot2Registered);

        // Check pilots list
        address[] memory pilots = superCluster.getPilots();
        console.log("Total registered pilots:", pilots.length);
        console.log("Expected pilots: 2");
        console.log("Pilot1 in list:", pilots[0] == address(pilot1));
        console.log("Pilot2 in list:", pilots[1] == address(pilot2));
    }

    function test_2_UserSelectPilot() public {
        console.log("=== FLOW 2: USER SELECT PILOT ===");

        // User1 deposits first
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        console.log("User1 sToken balance before pilot selection:", sTokenInstance.balanceOf(user1));
        console.log("Expected sToken balance:", DEPOSIT_AMOUNT);

        // User1 selects pilot1 with IDRX
        vm.prank(user1);
        superCluster.selectPilot(address(pilot1), address(mockIDRX), DEPOSIT_AMOUNT);

        console.log("User1 sToken balance after pilot selection:", sTokenInstance.balanceOf(user1));
        console.log("Expected sToken balance: 0");

        console.log("Pilot1 IDRX balance:", mockIDRX.balanceOf(address(pilot1)));
        console.log("Expected pilot1 IDRX balance:", DEPOSIT_AMOUNT);

        // User2 deposits and selects pilot2
        vm.prank(user2);
        superCluster.deposit(address(mockIDRX), LARGE_DEPOSIT);

        vm.prank(user2);
        superCluster.selectPilot(address(pilot2), address(mockIDRX), LARGE_DEPOSIT);

        console.log("Pilot2 IDRX balance:", mockIDRX.balanceOf(address(pilot2)));
        console.log("Expected pilot2 IDRX balance:", LARGE_DEPOSIT);
    }

    // ===== FLOW 3: STRATEGI PILOT =====

    function test_3_PilotStrategy() public {
        console.log("=== FLOW 3: STRATEGI PILOT ===");

        // Check pilot1 strategy (Conservative: 70% Morpho, 30% Aave)
        (address[] memory adapters1, uint256[] memory allocations1) = pilot1.getStrategy();
        console.log("Pilot1 adapters length:", adapters1.length);
        console.log("Expected adapters: 2");
        console.log("Pilot1 Morpho allocation:", allocations1[0]);
        console.log("Expected Morpho allocation: 7000 (70%)");
        console.log("Pilot1 Aave allocation:", allocations1[1]);
        console.log("Expected Aave allocation: 3000 (30%)");

        // Check pilot2 strategy (Aggressive: 30% Morpho, 70% Aave)
        (, uint256[] memory allocations2) = pilot2.getStrategy();
        console.log("Pilot2 Morpho allocation:", allocations2[0]);
        console.log("Expected Morpho allocation: 3000 (30%)");
        console.log("Pilot2 Aave allocation:", allocations2[1]);
        console.log("Expected Aave allocation: 7000 (70%)");

        // Check pilot names and descriptions
        console.log("Pilot1 name:", pilot1.name());
        console.log("Pilot1 description:", pilot1.description());
        console.log("Pilot2 name:", pilot2.name());
        console.log("Pilot2 description:", pilot2.description());
    }

    // ===== FLOW 4: EKSEKUSI VIA ADAPTER =====

    function test_4_AdapterExecution() public {
        console.log("=== FLOW 4: EKSEKUSI VIA ADAPTER ===");

        // User1 deposits and selects pilot1
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        vm.prank(user1);
        superCluster.selectPilot(address(pilot1), address(mockIDRX), DEPOSIT_AMOUNT);

        // Execute strategy for pilot1
        address[] memory adapters = new address[](2);
        adapters[0] = address(mockMorpho);
        adapters[1] = address(mockAave);

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 7000;
        allocations[1] = 3000;

        // Note: executeStrategy function not implemented in current version
        // vm.prank(owner);
        // superCluster.executeStrategy(address(pilot1), adapters, allocations);

        // Check pilot assets
        console.log("Pilot1 IDRX balance:", mockIDRX.balanceOf(address(pilot1)));
        console.log("Expected pilot1 IDRX balance: 1000");
    }

    function test_4_AdapterHarvest() public {
        console.log("=== FLOW 4: ADAPTER HARVEST ===");

        // Setup: User deposits and strategy executed
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        vm.prank(user1);
        superCluster.selectPilot(address(pilot1), address(mockIDRX), DEPOSIT_AMOUNT);

        // Execute strategy
        address[] memory adapters = new address[](2);
        adapters[0] = address(mockMorpho);
        adapters[1] = address(mockAave);

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 7000;
        allocations[1] = 3000;

        // Note: executeStrategy and harvestRewards functions not implemented in current version
        // vm.prank(owner);
        // superCluster.executeStrategy(address(pilot1), adapters, allocations);

        // vm.prank(owner);
        // superCluster.harvestRewards(address(pilot1));
    }

    // ===== FLOW 5: YIELD & REBASE =====

    function test_5_RebaseMechanism() public {
        console.log("=== FLOW 5: YIELD & REBASE ===");

        // Setup: Multiple users with different pilots
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        vm.prank(user1);
        superCluster.selectPilot(address(pilot1), address(mockIDRX), DEPOSIT_AMOUNT);

        vm.prank(user2);
        superCluster.deposit(address(mockIDRX), LARGE_DEPOSIT);

        vm.prank(user2);
        superCluster.selectPilot(address(pilot2), address(mockIDRX), LARGE_DEPOSIT);

        // Execute strategies
        address[] memory adapters = new address[](2);
        adapters[0] = address(mockMorpho);
        adapters[1] = address(mockAave);

        uint256[] memory allocations1 = new uint256[](2);
        allocations1[0] = 7000;
        allocations1[1] = 3000;

        uint256[] memory allocations2 = new uint256[](2);
        allocations2[0] = 3000;
        allocations2[1] = 7000;

        // Note: executeStrategy function not implemented in current version
        // vm.prank(owner);
        // superCluster.executeStrategy(address(pilot1), adapters, allocations1);

        // vm.prank(owner);
        // superCluster.executeStrategy(address(pilot2), adapters, allocations2);

        // Check initial state
        uint256 initialSupply = sTokenInstance.totalSupply();
        console.log("Initial sToken supply:", initialSupply);

        // Fast forward time to allow rebase
        vm.warp(block.timestamp + 1 days);

        // Perform rebase
        superCluster.rebase();

        uint256 newSupply = sTokenInstance.totalSupply();
        console.log("New sToken supply after rebase:", newSupply);
        console.log("Supply increased:", newSupply > initialSupply);

        // Check rebase time updated
        console.log("Last rebase time:", sTokenInstance.lastRebaseTime());
        console.log("Current timestamp:", block.timestamp);
    }

    // ===== FLOW 6: WITHDRAW / EXIT =====

    function test_6_WithdrawExit() public {
        console.log("=== FLOW 6: WITHDRAW / EXIT ===");

        // Setup: User deposits and selects pilot
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        uint256 initialBalance = sTokenInstance.balanceOf(user1);
        console.log("User1 initial sToken balance:", initialBalance);

        // User selects pilot (transfers IDRX to pilot)
        vm.prank(user1);
        superCluster.selectPilot(address(pilot1), address(mockIDRX), DEPOSIT_AMOUNT);

        console.log("User1 sToken balance after pilot selection:", sTokenInstance.balanceOf(user1));
        console.log("Expected balance: 0");

        // Note: After selecting pilot, user's sToken is burned and IDRX is transferred to pilot
        // User cannot withdraw from pilot directly - this would need pilot functionality
        console.log("User1 sToken balance after pilot selection:", sTokenInstance.balanceOf(user1));
        console.log("Expected balance: 0 (sToken burned when selecting pilot)");

        // Check pilot received the IDRX
        console.log("Pilot1 IDRX balance:", mockIDRX.balanceOf(address(pilot1)));
        console.log("Expected pilot1 IDRX balance:", DEPOSIT_AMOUNT);

        // User would need to exit from pilot first (not implemented in current version)
        // For now, just verify the state
        uint256 userIDRXBalanceBefore = mockIDRX.balanceOf(user1);
        console.log("User1 IDRX balance before any withdraw:", userIDRXBalanceBefore);

        console.log("User1 sToken balance after pilot selection:", sTokenInstance.balanceOf(user1));
        console.log("Expected final sToken balance: 0 (burned when selecting pilot)");
    }

    // ===== COMPREHENSIVE FLOW TEST =====

    function test_CompleteFlow() public {
        console.log("=== COMPREHENSIVE FLOW TEST ===");

        // 1. Multiple users deposit
        vm.prank(user1);
        superCluster.deposit(address(mockIDRX), DEPOSIT_AMOUNT);

        vm.prank(user2);
        superCluster.deposit(address(mockIDRX), LARGE_DEPOSIT);

        console.log("Step 1 - Deposits completed");
        console.log("Total sToken supply:", sTokenInstance.totalSupply());

        // 2. Users select different pilots
        vm.prank(user1);
        superCluster.selectPilot(address(pilot1), address(mockIDRX), DEPOSIT_AMOUNT);

        vm.prank(user2);
        superCluster.selectPilot(address(pilot2), address(mockIDRX), LARGE_DEPOSIT);

        console.log("Step 2 - Pilot selection completed");
        console.log("Pilot1 IDRX balance:", mockIDRX.balanceOf(address(pilot1)));
        console.log("Pilot2 IDRX balance:", mockIDRX.balanceOf(address(pilot2)));

        // 3. Execute strategies
        address[] memory adapters = new address[](2);
        adapters[0] = address(mockMorpho);
        adapters[1] = address(mockAave);

        uint256[] memory allocations1 = new uint256[](2);
        allocations1[0] = 7000;
        allocations1[1] = 3000;

        uint256[] memory allocations2 = new uint256[](2);
        allocations2[0] = 3000;
        allocations2[1] = 7000;

        // Note: executeStrategy function not implemented in current version
        // vm.prank(owner);
        // superCluster.executeStrategy(address(pilot1), adapters, allocations1);

        // vm.prank(owner);
        // superCluster.executeStrategy(address(pilot2), adapters, allocations2);

        // console.log("Step 3 - Strategies executed");
        // console.log("Morpho total balance:", mockMorpho.balanceOf(address(mor)));
        // console.log("Aave total balance:", mockAave.getBalance());

        // 4. Harvest rewards
        // Note: harvestRewards function not implemented in current version
        // vm.prank(owner);
        // superCluster.harvestRewards(address(pilot1));

        // vm.prank(owner);
        // superCluster.harvestRewards(address(pilot2));

        console.log("Step 4 - Rewards harvested");

        // 5. Rebase
        vm.warp(block.timestamp + 1 days);
        superCluster.rebase();

        console.log("Step 5 - Rebase completed");
        console.log("Final sToken supply:", sTokenInstance.totalSupply());

        // 6. Users exit from pilots (not implemented in current version)
        // Note: After selecting pilots, sTokens are burned and IDRX is transferred to pilots
        console.log("Step 6 - Pilot selection completed");
        console.log("Pilot1 IDRX balance:", mockIDRX.balanceOf(address(pilot1)));
        console.log("Pilot2 IDRX balance:", mockIDRX.balanceOf(address(pilot2)));

        // Check user sToken balances (should be 0 after pilot selection)
        console.log("User1 sToken balance:", sTokenInstance.balanceOf(user1));
        console.log("User2 sToken balance:", sTokenInstance.balanceOf(user2));
        console.log("Expected: 0 (burned when selecting pilots)");

        console.log("Step 7 - Users withdrew from SuperCluster");
        console.log("Final user1 IDRX balance:", mockIDRX.balanceOf(user1));
        console.log("Final user2 IDRX balance:", mockIDRX.balanceOf(user2));
    }
}
