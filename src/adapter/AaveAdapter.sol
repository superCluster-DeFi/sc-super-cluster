// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Adapter} from "./Adapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LendingPool} from "../mocks/MockAave.sol";

contract AaveAdapter is Adapter {
    LendingPool public immutable LENDINGPOOL;

    constructor(address _token, address _protocolAddress, string memory _protocolName, string memory _pilotStrategy)
        Adapter(_token, _protocolAddress, _protocolName, _pilotStrategy)
    {
        LENDINGPOOL = LendingPool(_protocolAddress);
    }

    /**
     * @dev DEPOSIT: Supply to MockAave
     */
    function deposit(uint256 amount) external override onlyActive returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Transfer from caller (Pilot)
        bool status = IERC20(TOKEN).transferFrom(msg.sender, address(this), amount);
        require(status, "Transfer failed");

        // Approve MockAave
        IERC20(TOKEN).approve(PROTOCOL_ADDRESS, amount);

        // Supply to MockAave - this will emit Supply event
        LENDINGPOOL.supply(amount);

        // In MockAave, shares = amount when totalSupplyShares == 0
        // Otherwise shares = (amount * totalSupplyShares) / totalSupplyAssets
        shares = amount; // Simplified for now

        // Update internal tracking
        _updateTotalDeposited(amount, true);

        emit Deposited(amount);
        return shares;
    }

    /**
     * @dev WITHDRAW: Withdraw from MockAave
     */
    function withdrawTo(address to, uint256 amount) external override onlyActive returns (uint256) {
        if (amount == 0) revert InvalidAmount();

        uint256 shares = convertToShares(amount);
        uint256 currentShares = LENDINGPOOL.getUserSupplyShares(address(this));

        if (currentShares < shares) revert InsufficientBalance();

        //save current balance
        uint256 balanceBefore = IERC20(TOKEN).balanceOf(address(this));

        // withdraw from MockAave - this will emit Withdraw event
        LENDINGPOOL.withdraw(shares);

        // update balance
        uint256 balanceAfter = IERC20(TOKEN).balanceOf(address(this));
        uint256 withdrawnAmount = balanceAfter - balanceBefore;

        // Transfer to caller
        bool status = IERC20(TOKEN).transfer(to, withdrawnAmount);
        require(status, "Transfer failed");

        // Update tracking
        _updateTotalDeposited(withdrawnAmount, false);

        emit Withdrawn(withdrawnAmount);
    }

    /**
     * @dev WITHDRAW: Basic withdrawal to msg.sender
     */
    function withdraw(uint256 shares) external override onlyActive returns (uint256 amount) {
        if (shares == 0) revert InvalidAmount();

        uint256 currentShares = LENDINGPOOL.getUserSupplyShares(address(this));
        if (currentShares < shares) revert InsufficientBalance();

        // Get balance before
        uint256 balanceBefore = IERC20(TOKEN).balanceOf(address(this));

        // Withdraw from protocol
        LENDINGPOOL.withdraw(shares);

        // Calculate received amount
        uint256 balanceAfter = IERC20(TOKEN).balanceOf(address(this));
        amount = balanceAfter - balanceBefore;

        // Transfer to caller
        bool status = IERC20(TOKEN).transfer(msg.sender, amount);
        require(status, "Transfer failed");

        // Update internal tracking
        _updateTotalDeposited(amount, false);

        emit Withdrawn(amount);
        return amount;
    }

    /**
     * @dev GET BALANCE: Get current supply balance in assets
     */
    function getBalance() external view override returns (uint256) {
        return LENDINGPOOL.getUserSupplyBalance(address(this));
    }

    /**
     * @dev GET SUPPLY SHARES: Get raw supply shares
     */
    function getSupplyShares() external view returns (uint256) {
        return LENDINGPOOL.getUserSupplyShares(address(this));
    }

    /**
     * @dev Convert assets to shares based on current exchange rate
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        if (assets == 0) return 0;

        // Get current exchange rate from MockAave
        uint256 totalSupplyAssets = LENDINGPOOL.totalSupplyAssets();
        uint256 totalSupplyShares = LENDINGPOOL.totalSupplyShares();

        if (totalSupplyAssets == 0 || totalSupplyShares == 0) {
            return assets; // 1:1 if no existing supply
        }

        // Calculate: assets * totalShares / totalSupplyAssets
        return (assets * totalSupplyShares) / totalSupplyAssets;
    }

    /**
     * @dev Convert shares to assets based on current exchange rate
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (shares == 0) return 0;

        uint256 totalSupplyAssets = LENDINGPOOL.totalSupplyAssets();
        uint256 totalSupplyShares = LENDINGPOOL.totalSupplyShares();

        if (totalSupplyAssets == 0 || totalSupplyShares == 0) {
            return shares; // 1:1 if no existing supply
        }

        // Calculate: shares * totalSupplyAssets / totalShares
        return (shares * totalSupplyAssets) / totalSupplyShares;
    }

    /**
     * @dev IAdapter compliance - Mock implementations
     */
    function getPendingRewards() external pure override returns (uint256) {
        return 0; // MockAave doesn't have external rewards
    }

    function harvest() external pure override returns (uint256) {
        return 0; // No harvest in MockAave
    }

    /**
     * @dev Get lending pool info
     */
    function getLendingPoolInfo()
        external
        view
        returns (
            uint256 totalSupplyAssets,
            uint256 totalSupplyShares,
            uint256 totalBorrowAssets,
            uint256 totalBorrowShares
        )
    {
        totalSupplyAssets = LENDINGPOOL.totalSupplyAssets();
        totalSupplyShares = LENDINGPOOL.totalSupplyShares();
        totalBorrowAssets = LENDINGPOOL.totalBorrowAssets();
        totalBorrowShares = LENDINGPOOL.totalBorrowShares();
    }

    /**
     * @dev Manually accrue interest
     */
    function accureInterest() external {
        LENDINGPOOL.accureInterest();
    }

    function getTotalAssets() external view override returns (uint256) {
        // Return the protocol-held supply balance for this adapter
        return LENDINGPOOL.getUserSupplyBalance(address(this));
    }
}
