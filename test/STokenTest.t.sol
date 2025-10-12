// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
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

        // Deploy mock tokens
        idrx = new MockIDRX();
        usdc = new MockUSDC();
        console.log("Deployed mock tokens - IDRX:", address(idrx), "USDC:", address(usdc));

        // Deploy SToken with USDC as underlying token
        token = new SToken("sUSDC", "sUSDC", address(usdc));
        wrappedToken = new WsToken(address(token));
        console.log("Deployed SToken:", address(token), "wsToken:", address(wrappedToken));

        // Set authorized minter
        token.setAuthorizedMinter(address(this), true);

        // Mint some underlying tokens to users
        idrx.mint(user1, 1000e18);
        idrx.mint(user2, 1000e18);
        usdc.mint(user1, 1000e6);
        usdc.mint(user2, 1000e6);
    }

    function test_mint() public {
        console.log("=== Testing mint function ===");

        // Test first mint (1:1 ratio)
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);
        console.log("After minting 100e18 to user1");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("User1 shares:", token.sharesOf(user1));
        console.log("Total shares:", token.totalShares());
        console.log("Total AUM:", token.totalAssetsUnderManagement());

        assertEq(token.balanceOf(user1), 100e18);
        assertEq(token.sharesOf(user1), 100e18);
        assertEq(token.totalShares(), 100e18);
        assertEq(token.totalSupply(), token.totalAssetsUnderManagement());
    }

    function test_mintAfterRebase() public {
        console.log("=== Testing mint after rebase ===");

        // Initial mint
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);

        // Simulate profit - AUM increases to 120
        token.updateAssetsUnderManagement(120e18);

        console.log("After rebase simulation:");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("Total AUM:", token.totalAssetsUnderManagement());

        // New user mints at higher price
        token.mint(user2, 60e18); // Should get fewer shares
        token.updateAssetsUnderManagement(180e18);

        console.log("After user2 mint:");
        console.log("User2 balance:", token.balanceOf(user2));
        console.log("User2 shares:", token.sharesOf(user2));
        console.log("User1 shares (unchanged):", token.sharesOf(user1));

        // user2 should get 60 * 100 / 120 = 50 shares
        assertEq(token.sharesOf(user2), 50e18);
        assertEq(token.balanceOf(user2), 60e18);
    }

    function test_burn() public {
        console.log("=== Testing burn function ===");

        // First mint some tokens
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);

        uint256 initialShares = token.sharesOf(user1);
        console.log("Initial shares:", initialShares);
        console.log("Initial balance:", token.balanceOf(user1));

        // Burn some tokens
        token.burn(user1, 50e18);

        //  Manually reduce AUM after burn
        token.updateAssetsUnderManagement(50e18);

        console.log("After burning 50e18:");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("User1 shares:", token.sharesOf(user1));
        console.log("Total AUM:", token.totalAssetsUnderManagement());

        assertEq(token.balanceOf(user1), 50e18);
        assertEq(token.sharesOf(user1), 50e18);
    }

    function test_rebase() public {
        console.log("=== Testing rebase mechanism ===");

        // Setup: mint tokens to user1
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);

        console.log("Initial state:");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("User1 shares:", token.sharesOf(user1));
        console.log("Total AUM:", token.totalAssetsUnderManagement());

        // Simulate harvest profit - AUM increases by 50%
        token.updateAssetsUnderManagement(150e18);

        console.log("After AUM update (rebase):");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("User1 shares (unchanged):", token.sharesOf(user1));
        console.log("Total AUM:", token.totalAssetsUnderManagement());
        console.log("Total supply:", token.totalSupply());

        // Balance should automatically increase, shares stay same
        assertEq(token.balanceOf(user1), 150e18); // 50% increase
        assertEq(token.sharesOf(user1), 100e18); // shares unchanged
        assertEq(token.totalSupply(), 150e18); // total supply = AUM
    }

    function test_multiUserRebase() public {
        console.log("=== Testing multi-user rebase ===");

        // User1 deposits first
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);

        // User2 deposits later
        token.mint(user2, 100e18);
        token.updateAssetsUnderManagement(200e18);

        console.log("Before rebase:");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("User2 balance:", token.balanceOf(user2));
        console.log("User1 shares:", token.sharesOf(user1));
        console.log("User2 shares:", token.sharesOf(user2));

        // Simulate 20% profit
        token.updateAssetsUnderManagement(240e18);

        console.log("After 20% profit:");
        console.log("User1 balance:", token.balanceOf(user1));
        console.log("User2 balance:", token.balanceOf(user2));
        console.log("Total supply:", token.totalSupply());

        // Both users should get proportional gains
        assertEq(token.balanceOf(user1), 120e18); // 100 * 1.2
        assertEq(token.balanceOf(user2), 120e18); // 100 * 1.2
        assertEq(token.totalSupply(), 240e18);
    }

    function test_shareCalculations() public {
        console.log("=== Testing share calculations ===");

        // Initial mint - 1:1 ratio
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);
        assertEq(token.sharesOf(user1), 100e18);

        // AUM increases - more valuable per share
        token.updateAssetsUnderManagement(150e18);

        // New user should get fewer shares for same amount
        token.mint(user2, 75e18); // At 1.5x price should get 50 shares

        console.log("User2 shares for 75e18 at 1.5x price:", token.sharesOf(user2));
        assertEq(token.sharesOf(user2), 50e18);
    }

    function test_unauthorizedMinter() public {
        console.log("=== Testing unauthorized minter ===");

        vm.prank(user1);
        vm.expectRevert("Unauthorized");
        token.mint(user1, 100e18);
    }

    function test_dynamicNaming() public {
        console.log("=== Testing dynamic naming ===");

        console.log("Current SToken name:", token.name());
        console.log("Current SToken symbol:", token.symbol());

        // Create new token with different underlying
        SToken idrxToken = new SToken("sIDRX", "sIDRX", address(idrx));
        console.log("IDRX SToken name:", idrxToken.name());
        console.log("IDRX SToken symbol:", idrxToken.symbol());

        assertEq(token.name(), "sUSDC");
        assertEq(token.symbol(), "sUSDC");
        assertEq(idrxToken.name(), "sIDRX");
        assertEq(idrxToken.symbol(), "sIDRX");
    }

    // Remove old rebase timing tests since there's no interval anymore
    // Remove rebaseNotReady and rebaseInterval tests

    function test_burnInsufficientBalance() public {
        console.log("=== Testing burn with insufficient balance ===");

        vm.expectRevert("Insufficient balance");
        token.burn(user1, 100e18);
    }

    function test_shareConsistency() public {
        console.log("=== Testing share consistency ===");

        // Multiple users, multiple rebases
        token.mint(user1, 100e18);
        token.updateAssetsUnderManagement(100e18);

        token.mint(user2, 200e18);
        token.updateAssetsUnderManagement(300e18);

        uint256 user1SharesBefore = token.sharesOf(user1);
        uint256 user2SharesBefore = token.sharesOf(user2);

        // Multiple rebases
        token.updateAssetsUnderManagement(360e18); // +20%
        token.updateAssetsUnderManagement(432e18); // +20% again

        // Shares should never change
        assertEq(token.sharesOf(user1), user1SharesBefore);
        assertEq(token.sharesOf(user2), user2SharesBefore);

        // But balances should increase
        assertGt(token.balanceOf(user1), 100e18);
        assertGt(token.balanceOf(user2), 200e18);
    }
}
