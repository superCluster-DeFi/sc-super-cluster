// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SToken} from "./tokens/SToken.sol";
import {IPilot} from "./interfaces/IPilot.sol";

import {console} from "forge-std/console.sol";

contract SuperCluster is Ownable, ReentrancyGuard {
    SToken public underlyingToken; // SToken token (rebasing)
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenBalances;

    // Pilot management
    mapping(address => bool) public registeredPilots;
    address[] public pilots;

    // Events
    event PilotRegistered(address indexed pilot);
    event TokenDeposited(address indexed token, address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed user, uint256 amount);
    event TokenSupported(address indexed token, bool supported);
    event PilotSelected(address indexed pilot, address indexed token, uint256 amount);

    // Errors
    error PilotNotRegistered();
    error PilotAlreadyRegistered();
    error InsufficientBalance();
    error TransferFailed();
    error TokenNotSupported();
    error AmountMustBeGreaterThanZero();

    constructor(address underlyingToken_) Ownable(msg.sender) {
        // Get token metadata from the underlying token
        IERC20Metadata tokenMetadata = IERC20Metadata(underlyingToken_);
        string memory tokenName = tokenMetadata.name();
        string memory tokenSymbol = tokenMetadata.symbol();

        // Deploy sToken with dynamic name and symbol
        underlyingToken = new SToken(
            string(abi.encodePacked("s", tokenName)),
            string(abi.encodePacked("s", tokenSymbol)),
            underlyingToken_,
            underlyingToken_
        );

        // Set this contract as authorized minter for the sToken
        underlyingToken.setAuthorizedMinter(address(this), true);

        // Add supported tokens
        supportedTokens[underlyingToken_] = true;
    }

    /**
     * @dev Trigger rebase on the underlying sToken by calculating current AUM
     */
    function rebase() external {
        uint256 newAUM = calculateTotalAUM();
        underlyingToken.rebase(newAUM);
    }

    /**
     * @dev Manual rebase with specific AUM (for testing/admin)
     */
    function rebaseWithAUM(uint256 newAUM) external onlyOwner {
        underlyingToken.rebase(newAUM);
    }

    /**
     * @dev Calculate total Assets Under Management across all pilots
     */
    function calculateTotalAUM() public view returns (uint256) {
        uint256 totalAUM = 0;

        //  Check actual token balance in contract
        address underlyingTokenAddress = underlyingToken.underlyingToken();
        totalAUM += IERC20(underlyingTokenAddress).balanceOf(address(this));

        // Add assets managed by all pilots
        for (uint256 i = 0; i < pilots.length; i++) {
            totalAUM += IPilot(pilots[i]).getTotalValue();
        }

        return totalAUM;
    }

    /**
     * @dev Universal deposit function for any supported token
     */
    function deposit(address token, uint256 amount) external {
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();

        // Transfer token from user to this contract
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        // Update token balance
        tokenBalances[token] += amount;

        // Mint sToken to user and update assets under management
        underlyingToken.mint(msg.sender, amount);
        underlyingToken.updateAssetsUnderManagement(underlyingToken.totalSupply());
        console.log("User sToken balance after mint:", underlyingToken.balanceOf(msg.sender));

        emit TokenDeposited(token, msg.sender, amount);
    }

    /**
     * @dev Universal withdraw function for any supported token
     */
    function withdraw(address token, uint256 amount) external {
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (tokenBalances[token] < amount) revert InsufficientBalance();
        if (underlyingToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Update token balance
        tokenBalances[token] -= amount;

        // Burn sToken from user and update assets under management
        underlyingToken.burn(msg.sender, amount);
        underlyingToken.updateAssetsUnderManagement(underlyingToken.totalSupply());

        // Transfer token to user
        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "Transfer failed");

        emit TokenWithdrawn(token, msg.sender, amount);
    }

    /**
     * @dev User selects a pilot for their funds using any supported token
     */
    function selectPilot(address pilot, address token, uint256 amount) external {
        if (!registeredPilots[pilot]) revert PilotNotRegistered();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (tokenBalances[token] < amount) revert InsufficientBalance();
        console.log("User sToken balance:", underlyingToken.balanceOf(msg.sender));
        if (underlyingToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Update token balance
        tokenBalances[token] -= amount;

        // Burn sToken from user and update assets under management
        underlyingToken.burn(msg.sender, amount);
        bool status = IERC20(token).transfer(pilot, amount);
        require(status, "Transfer failed");

        emit PilotSelected(pilot, token, amount);
    }

    /**
     * @dev Get all registered pilots
     */
    function getPilots() external view returns (address[] memory) {
        return pilots;
    }

    /**
     * @dev Register a new pilot (only owner)
     */
    function registerPilot(address pilot, address acceptedToken) external onlyOwner {
        require(!registeredPilots[pilot], "Pilot already registered");

        registeredPilots[pilot] = true;
        pilots.push(pilot);
        supportedTokens[acceptedToken] = true;

        emit PilotRegistered(pilot);
    }
}
