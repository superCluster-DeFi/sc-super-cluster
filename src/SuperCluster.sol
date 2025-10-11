// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SToken} from "./tokens/SToken.sol";

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
            SToken.STokenConfig(
                string(abi.encodePacked("s", tokenName)), string(abi.encodePacked("s", tokenSymbol)), underlyingToken_
            )
        );

        // Set this contract as authorized minter for the sToken
        underlyingToken.setAuthorizedMinter(address(this), true);

        // Add supported tokens
        supportedTokens[underlyingToken_] = true;
    }

    /**
     * @dev Trigger rebase on the underlying sToken
     */
    function rebase() external {
        underlyingToken.rebase();
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
        underlyingToken.updateAssetsUnderManagement(underlyingToken.getTotalAssetsUnderManagement() + amount);

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
        underlyingToken.updateAssetsUnderManagement(underlyingToken.getTotalAssetsUnderManagement() - amount);

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
        if (underlyingToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Update token balance
        tokenBalances[token] -= amount;

        // Burn sToken from user and update assets under management
        underlyingToken.burn(msg.sender, amount);
        underlyingToken.updateAssetsUnderManagement(underlyingToken.getTotalAssetsUnderManagement() - amount);

        emit PilotSelected(pilot, token, amount);
    }

    /**
     * @dev Get all registered pilots
     */
    function getPilots() external view returns (address[] memory) {
        return pilots;
    }
}
