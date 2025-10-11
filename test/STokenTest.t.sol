// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SToken} from "../src/tokens/SToken.sol";
import {WsToken} from "../src/tokens/WsToken.sol";
import {MockIDRX} from "../src/mocks/tokens/MockIDRX.sol";
import {MockUSDC} from "../src/mocks/tokens/MockUSDC.sol";

contract sTokenTest is Test {
    SToken public token;
    WsToken public wrappedToken;

    MockIDRX public idrx;
    MockUSDC public usdc;

    address public owner;

    address public user1;
    address public user2;

    function setUp() public {
        console.log("=== Setting up test environment ===");

        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        // console.log("Created addresses - owner:", owner, "user1:", user1, "user2:", user2);

        // Deploy mock tokens
        idrx = new MockIDRX();
        usdc = new MockUSDC();
        console.log("Deployed mock tokens - IDRX:", address(idrx), "USDC:", address(usdc));

        // Deploy SToken with USDC as underlying token (test contract becomes owner)
        token = new SToken(SToken.STokenConfig("SToken", "SToken", address(usdc)));
        wrappedToken = new WsToken(address(token));
        console.log("Deployed SToken:", address(token), "wsToken:", address(wrappedToken));
        console.log("SToken name:", token.name(), "symbol:", token.symbol());
        console.log("SToken underlying token:", token.underlyingToken());
        console.log("Expected name should be 'sUSDC' since underlying is USDC");

        // Set authorized minter for SToken (test contract is already owner)
        token.setAuthorizedMinter(address(this), true);

        // Mint some underlying tokens to users
        idrx.mint(user1, 1000e18);
        idrx.mint(user2, 1000e18);
        usdc.mint(user1, 1000e6);
        usdc.mint(user2, 1000e6);
        console.log("Minted underlying tokens to users");
        console.log("User1 IDRX balance:", idrx.balanceOf(user1));
        console.log("User1 USDC balance:", usdc.balanceOf(user1));
    }

    function test_mint() public {
        console.log("=== Testing mint function ===");
        console.log("Initial user1 balance:", token.balanceOf(user1));
        console.log("Initial total supply:", token.totalSupply());

        // Test minting SToken
        token.mint(user1, 100e18);
        console.log("After minting 100e18 to user1");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("Total supply:", token.totalSupply());

        console.log(" User1 balance matches expected:", token.balanceOf(user1) == 100e18);
        console.log(" Total supply matches expected:", token.totalSupply() == 100e18);
    }

    function test_burn() public {
        console.log("=== Testing burn function ===");

        // First mint some tokens
        token.mint(user1, 100e18);
        console.log("After minting 100e18 to user1");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("Total supply:", token.totalSupply());
        console.log(" Initial balance correct:", token.balanceOf(user1) == 100e18);

        // Then burn some tokens
        token.burn(user1, 50e18);
        console.log("After burning 50e18 from user1");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("Total supply:", token.totalSupply());

        console.log(" Final balance correct:", token.balanceOf(user1) == 50e18);
        console.log(" Final supply correct:", token.totalSupply() == 50e18);
    }

    function test_rebase() public {
        console.log("=== Testing rebase function ===");

        // Mint initial tokens
        token.mint(user1, 100e18);
        console.log("After minting 100e18 to user1");
        console.log("Total supply:", token.totalSupply());
        console.log("Assets under management:", token.getTotalAssetsUnderManagement());
        console.log(" Initial supply correct:", token.totalSupply() == 100e18);

        // Update assets under management (simulating growth)
        token.updateAssetsUnderManagement(150e18);
        console.log("After updating assets under management to 150e18");
        console.log("Assets under management:", token.getTotalAssetsUnderManagement());
        console.log(" Assets under management correct:", token.getTotalAssetsUnderManagement() == 150e18);

        // Fast forward time to allow rebase
        console.log("Current timestamp:", block.timestamp);
        vm.warp(block.timestamp + 1 days + 1);
        console.log("After warping time by 1 day + 1 second");
        console.log("New timestamp:", block.timestamp);

        // Execute rebase
        console.log("Executing rebase...");
        token.rebase();
        console.log("After rebase");
        console.log("Total supply:", token.totalSupply());
        console.log("Assets under management:", token.getTotalAssetsUnderManagement());

        // Check that total supply now matches assets under management
        console.log(" Final supply matches assets:", token.totalSupply() == 150e18);
        console.log(" Assets under management unchanged:", token.getTotalAssetsUnderManagement() == 150e18);
    }

    function test_rebaseNotReady() public {
        console.log("=== Testing rebase not ready ===");
        console.log("Current timestamp:", block.timestamp);
        console.log("Last rebase time:", token.lastRebaseTime());
        console.log("Rebase interval:", token.getRebaseInterval());

        // Try to rebase before interval has passed
        console.log("Attempting rebase before interval...");
        vm.expectRevert(SToken.RebaseNotReady.selector);
        token.rebase();
    }

    function test_unauthorizedMinter() public {
        console.log("=== Testing unauthorized minter ===");
        console.log("Attempting to mint as user1 (unauthorized)...");

        // Test that unauthorized address cannot mint
        vm.prank(user1);
        vm.expectRevert(SToken.UnauthorizedMinter.selector);
        token.mint(user1, 100e18);
    }

    function test_setUnderlyingToken() public {
        console.log("=== Testing set underlying token ===");
        console.log("Current underlying token:", token.underlyingToken());

        // Test setting underlying token (test contract is owner)
        token.setUnderlyingToken(address(idrx));
        console.log("After setting underlying token to IDRX");
        console.log("New underlying token:", token.underlyingToken());

        console.log(" Underlying token changed correctly:", token.underlyingToken() == address(idrx));
    }

    function test_rebaseInterval() public {
        console.log("=== Testing rebase interval ===");
        console.log("Rebase interval:", token.getRebaseInterval());
        console.log(" Rebase interval correct:", token.getRebaseInterval() == 1 days);
    }

    function test_dynamicNaming() public {
        console.log("=== Testing dynamic naming ===");

        // Test with USDC (current token)
        console.log("Current SToken name:", token.name());
        console.log("Current SToken symbol:", token.symbol());
        console.log("Underlying token symbol:", IERC20Metadata(token.underlyingToken()).symbol());

        // Create a new SToken with IDRX to test different naming
        SToken idrxToken = new SToken(SToken.STokenConfig("SToken", "SToken", address(idrx)));
        console.log("IDRX SToken name:", idrxToken.name());
        console.log("IDRX SToken symbol:", idrxToken.symbol());
        console.log("IDRX underlying token symbol:", IERC20Metadata(idrxToken.underlyingToken()).symbol());

        // Verify naming convention
        console.log(" USDC token name correct:", keccak256(bytes(token.name())) == keccak256(bytes("sUSDC")));
        console.log(" USDC token symbol correct:", keccak256(bytes(token.symbol())) == keccak256(bytes("sUSDC")));
        console.log(" IDRX token name correct:", keccak256(bytes(idrxToken.name())) == keccak256(bytes("sIDRX")));
        console.log(" IDRX token symbol correct:", keccak256(bytes(idrxToken.symbol())) == keccak256(bytes("sIDRX")));
    }

    function test_wrap() public {
        console.log("=== Testing wrap function ===");

        // First mint some SToken to user1
        token.mint(user1, 100e18);
        console.log("Minted 100e18 SToken to user1");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));

        // User1 approves wsToken contract to spend SToken
        vm.prank(user1);
        token.approve(address(wrappedToken), 50e18);
        console.log("User1 approved 50e18 SToken to wsToken contract");

        // Check exchange rate before wrapping
        console.log("Exchange rate before wrap:", wrappedToken.getExchangeRate());
        console.log("Expected wsToken amount:", wrappedToken.sTokenToWsToken(50e18));

        // User1 wraps 50e18 SToken to wsToken
        vm.prank(user1);
        wrappedToken.wrap(50e18);
        console.log("After wrapping 50e18 SToken to wsToken");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());
        console.log("Total SToken deposited:", wrappedToken.getTotalSTokenDeposited());

        console.log(" SToken balance correct:", token.balanceOf(user1) == 50e18);
        console.log(" wsToken balance correct:", wrappedToken.balanceOf(user1) == 50e18);
        console.log(" wsToken contract balance correct:", wrappedToken.getSTokenBalance() == 50e18);
        console.log(" total deposited correct:", wrappedToken.getTotalSTokenDeposited() == 50e18);
    }

    function test_unwrap() public {
        console.log("=== Testing unwrap function ===");

        // First mint and wrap some tokens
        token.mint(user1, 100e18);
        vm.prank(user1);
        token.approve(address(wrappedToken), 100e18);
        vm.prank(user1);
        wrappedToken.wrap(100e18);

        console.log("After initial wrap:");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());

        // User1 unwraps 30e18 wsToken back to SToken
        vm.prank(user1);
        wrappedToken.unwrap(30e18);
        console.log("After unwrapping 30e18 wsToken to SToken");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());

        console.log(" SToken balance correct:", token.balanceOf(user1) == 70e18);
        console.log(" wsToken balance correct:", wrappedToken.balanceOf(user1) == 70e18);
        console.log(" wsToken contract balance correct:", wrappedToken.getSTokenBalance() == 70e18);
    }

    function test_wrapInsufficientBalance() public {
        console.log("=== Testing wrap with insufficient balance ===");

        // Try to wrap without having SToken
        vm.prank(user1);
        vm.expectRevert("Insufficient sToken balance");
        wrappedToken.wrap(100e18);
        console.log("Correctly failed to wrap with insufficient balance");
    }

    function test_unwrapInsufficientBalance() public {
        console.log("=== Testing unwrap with insufficient balance ===");

        // Try to unwrap without having wsToken
        vm.prank(user1);
        vm.expectRevert("Insufficient wsToken balance");
        wrappedToken.unwrap(100e18);
        console.log("Correctly failed to unwrap with insufficient balance");
    }

    function test_wsTokenNaming() public {
        console.log("=== Testing wsToken naming ===");

        console.log("wsToken name:", wrappedToken.name());
        console.log("wsToken symbol:", wrappedToken.symbol());
        console.log("SToken symbol:", token.symbol());

        console.log(" wsToken name correct:", keccak256(bytes(wrappedToken.name())) == keccak256(bytes("wsUSDC")));
        console.log(" wsToken symbol correct:", keccak256(bytes(wrappedToken.symbol())) == keccak256(bytes("wsUSDC")));
    }

    function test_fullWrapUnwrapCycle() public {
        console.log("=== Testing full wrap/unwrap cycle ===");

        // Initial state
        console.log("Initial state:");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));

        // Mint SToken
        token.mint(user1, 200e18);
        console.log("After minting 200e18 SToken:");
        console.log("User1 SToken balance:", token.balanceOf(user1));

        // Wrap all SToken
        vm.prank(user1);
        token.approve(address(wrappedToken), 200e18);
        vm.prank(user1);
        wrappedToken.wrap(200e18);
        console.log("After wrapping all SToken:");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());

        // Unwrap half
        vm.prank(user1);
        wrappedToken.unwrap(100e18);
        console.log("After unwrapping half:");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());

        // Unwrap remaining
        vm.prank(user1);
        wrappedToken.unwrap(100e18);
        console.log("After unwrapping remaining:");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());

        console.log(" Final SToken balance correct:", token.balanceOf(user1) == 200e18);
        console.log(" Final wsToken balance correct:", wrappedToken.balanceOf(user1) == 0);
        console.log(" Final contract balance correct:", wrappedToken.getSTokenBalance() == 0);
    }

    function test_rebaseAwareWrapping() public {
        console.log("=== Testing rebase-aware wrapping ===");

        // User1 wraps 100e18 SToken initially
        token.mint(user1, 100e18);
        vm.prank(user1);
        token.approve(address(wrappedToken), 100e18);
        vm.prank(user1);
        wrappedToken.wrap(100e18);

        console.log("After initial wrap:");
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("Total SToken deposited:", wrappedToken.getTotalSTokenDeposited());
        console.log("Exchange rate:", wrappedToken.getExchangeRate());

        // Simulate a rebase that increases SToken supply by 20%
        console.log("Simulating rebase (20% increase)...");
        token.updateAssetsUnderManagement(120e18); // 20% increase
        vm.warp(block.timestamp + 1 days + 1);
        token.rebase();

        console.log("After rebase:");
        console.log("SToken total supply:", token.totalSupply());
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());
        console.log("Total SToken deposited (unchanged):", wrappedToken.getTotalSTokenDeposited());
        console.log("New exchange rate:", wrappedToken.getExchangeRate());

        // User2 wraps 50e18 SToken after rebase
        token.mint(user2, 50e18);
        vm.prank(user2);
        token.approve(address(wrappedToken), 50e18);
        vm.prank(user2);
        wrappedToken.wrap(50e18);

        console.log("After user2 wraps 50e18 SToken:");
        console.log("User2 wsToken balance:", wrappedToken.balanceOf(user2));
        console.log("User1 wsToken balance (unchanged):", wrappedToken.balanceOf(user1));
        console.log("Total wsToken supply:", wrappedToken.totalSupply());
        console.log("Total SToken deposited:", wrappedToken.getTotalSTokenDeposited());

        // User1 unwraps their wsToken
        uint256 user1WsTokenBalance = wrappedToken.balanceOf(user1);
        console.log("User1 unwrapping", user1WsTokenBalance, "wsToken");
        console.log("Expected SToken amount:", wrappedToken.wsTokenToSToken(user1WsTokenBalance));

        vm.prank(user1);
        wrappedToken.unwrap(user1WsTokenBalance);

        console.log("After user1 unwraps:");
        console.log("User1 SToken balance:", token.balanceOf(user1));
        console.log("User1 wsToken balance:", wrappedToken.balanceOf(user1));
        console.log("Remaining wsToken supply:", wrappedToken.totalSupply());
        console.log("Remaining SToken deposited:", wrappedToken.getTotalSTokenDeposited());

        // Verify that user1 got more SToken back due to rebase
        console.log(" User1 got more SToken due to rebase:", token.balanceOf(user1) > 100e18);
        console.log(" User1 SToken balance > 100e18:", token.balanceOf(user1) > 100e18);
    }

    function test_exchangeRateCalculations() public {
        console.log("=== Testing exchange rate calculations ===");

        // Test initial 1:1 rate
        console.log("Initial exchange rate (should be 1:1):", wrappedToken.getExchangeRate());
        console.log("SToken to wsToken (100e18):", wrappedToken.sTokenToWsToken(100e18));
        console.log("wsToken to SToken (100e18):", wrappedToken.wsTokenToSToken(100e18));

        // Wrap some tokens
        token.mint(user1, 100e18);
        vm.prank(user1);
        token.approve(address(wrappedToken), 100e18);
        vm.prank(user1);
        wrappedToken.wrap(100e18);

        console.log("After wrapping 100e18 SToken:");
        console.log("Exchange rate:", wrappedToken.getExchangeRate());
        console.log("Total wsToken supply:", wrappedToken.totalSupply());
        console.log("Total SToken deposited:", wrappedToken.getTotalSTokenDeposited());

        // Simulate rebase
        token.updateAssetsUnderManagement(150e18); // 50% increase
        vm.warp(block.timestamp + 1 days + 1);
        token.rebase();

        console.log("After 50% rebase:");
        console.log("SToken total supply:", token.totalSupply());
        console.log("wsToken contract SToken balance:", wrappedToken.getSTokenBalance());
        console.log("New exchange rate:", wrappedToken.getExchangeRate());
        console.log("SToken to wsToken (50e18):", wrappedToken.sTokenToWsToken(50e18));
        console.log("wsToken to SToken (50e18):", wrappedToken.wsTokenToSToken(50e18));

        // The exchange rate should now be higher (more SToken per wsToken)
        console.log(" Exchange rate increased after rebase:", wrappedToken.getExchangeRate() > 1e18);
    }
}
