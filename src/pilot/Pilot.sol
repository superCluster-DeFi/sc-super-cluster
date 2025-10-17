// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPilot} from "../interfaces/IPilot.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";

contract Pilot is IPilot, Ownable, ReentrancyGuard {
    string public override name;
    string public _description;
    address public immutable TOKEN;
    address public superClusterAddress;

    // Strategy tracking
    address[] public strategyAdapters;
    uint256[] public strategyAllocations;
    mapping(address => bool) public isActiveAdapter;

    // Events
    event StrategyUpdated(address[] adapters, uint256[] allocations);
    event Invested(uint256 amount, address[] adapters, uint256[] allocations);
    event Divested(uint256 amount, address[] adapters, uint256[] allocations);
    event Harvested(address[] adapters, uint256 totalHarvested);

    // Errors
    error InvalidAllocation();
    error AdapterNotActive();
    error InvalidArrayLength();
    error InsufficientBalance();
    error ZeroAmount();

    constructor(string memory _name, string memory __description, address _token) Ownable(msg.sender) {
        name = _name;
        _description = __description;
        TOKEN = _token;
    }

    /**
     * @dev Invest funds according to pilot's strategy
     */
    function invest(uint256 amount, address[] calldata adapters, uint256[] calldata allocations)
        external
        override
        onlyOwner
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (adapters.length != allocations.length) revert InvalidArrayLength();

        // Validate allocations sum to 10000 (100%)
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
            if (!isActiveAdapter[adapters[i]]) revert AdapterNotActive();
        }
        if (totalAllocation != 10000) revert InvalidAllocation();

        // Check TOKEN balance
        uint256 balance = IERC20(TOKEN).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        // Distribute funds to adapters
        for (uint256 i = 0; i < adapters.length; i++) {
            uint256 adapterAmount = (amount * allocations[i]) / 10000;
            if (adapterAmount > 0) {
                IERC20(TOKEN).approve(adapters[i], adapterAmount);
                IAdapter(adapters[i]).deposit(adapterAmount);
            }
        }

        emit Invested(amount, adapters, allocations);
    }

    /**
     * @dev Auto-invest funds from SuperCluster
     */
    function receiveAndInvest(uint256 amount) external override {
        require(msg.sender == superClusterAddress, "Only SuperCluster");

        // Auto-invest based on current strategy
        if (strategyAdapters.length > 0 && strategyAllocations.length > 0) {
            _distributeToAdapters(amount);
        }
        // If no strategy set, keep idle in pilot
    }

    /**
     * @dev Distribute to adapters based on allocation
     */
    function _distributeToAdapters(uint256 totalAmount) internal {
        for (uint256 i = 0; i < strategyAdapters.length; i++) {
            address adapter = strategyAdapters[i];
            uint256 allocation = strategyAllocations[i];

            if (allocation > 0 && isActiveAdapter[adapter]) {
                uint256 adapterAmount = (totalAmount * allocation) / 10000;

                if (adapterAmount > 0) {
                    // Transfer to adapter
                    bool status = IERC20(TOKEN).transfer(adapter, adapterAmount);
                    require(status, "Transfer failed");
                    // Trigger deposit
                    IAdapter(adapter).deposit(adapterAmount);
                }
            }
        }
    }

    /**
     * @dev Divest funds from external protocols
     */
    function divest(uint256 amount, address[] calldata adapters, uint256[] calldata allocations)
        external
        override
        onlyOwner
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (adapters.length != allocations.length) revert InvalidArrayLength();

        // Validate allocations sum to 10000 (100%)
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
            if (!isActiveAdapter[adapters[i]]) revert AdapterNotActive();
        }
        if (totalAllocation != 10000) revert InvalidAllocation();

        // Withdraw funds from adapters
        for (uint256 i = 0; i < adapters.length; i++) {
            uint256 adapterAmount = (amount * allocations[i]) / 10000;
            if (adapterAmount > 0) {
                // Convert amount to shares and withdraw
                uint256 shares = IAdapter(adapters[i]).convertToShares(adapterAmount);
                IAdapter(adapters[i]).withdraw(shares);
            }
        }

        emit Divested(amount, adapters, allocations);
    }

    /**
     * @dev Harvest rewards from external protocols
     */
    function harvest(address[] calldata adapters) external override onlyOwner nonReentrant {
        uint256 totalHarvested = 0;

        for (uint256 i = 0; i < adapters.length; i++) {
            if (!isActiveAdapter[adapters[i]]) revert AdapterNotActive();

            uint256 harvested = IAdapter(adapters[i]).harvest();
            totalHarvested += harvested;
        }

        emit Harvested(adapters, totalHarvested);
    }

    /**
     * @dev Get current strategy allocation
     */
    function getStrategy() external view override returns (address[] memory adapters, uint256[] memory allocations) {
        return (strategyAdapters, strategyAllocations);
    }

    /**
     * @dev Get pilot's description
     */
    function description() external view override returns (string memory) {
        return _description;
    }

    // Additional management functions
    function setPilot(string memory _name) external onlyOwner {
        name = _name;
    }

    function setDescription(string memory __description) external onlyOwner {
        _description = __description;
    }

    /**
     * @dev Set strategy allocation
     */
    function setPilotStrategy(address[] calldata adapters, uint256[] calldata allocations) external onlyOwner {
        if (adapters.length != allocations.length) revert InvalidArrayLength();

        // Validate allocations sum to 10000 (100%)
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < allocations.length; i++) {
            totalAllocation += allocations[i];
        }
        if (totalAllocation != 10000) revert InvalidAllocation();

        // Clear existing strategy
        for (uint256 i = 0; i < strategyAdapters.length; i++) {
            isActiveAdapter[strategyAdapters[i]] = false;
        }

        // Set new strategy
        strategyAdapters = adapters;
        strategyAllocations = allocations;

        for (uint256 i = 0; i < adapters.length; i++) {
            isActiveAdapter[adapters[i]] = true;
        }

        emit StrategyUpdated(adapters, allocations);
    }

    /**
     * @dev Add adapter to active list
     */
    function addAdapter(address adapter) external onlyOwner {
        isActiveAdapter[adapter] = true;
    }

    /**
     * @dev Remove adapter from active list
     */
    function removeAdapter(address adapter) external onlyOwner {
        isActiveAdapter[adapter] = false;
    }

    /**
     * @dev Emergency withdraw all IDRX tokens
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = IERC20(TOKEN).balanceOf(address(this));
        if (balance > 0) {
            bool status = IERC20(TOKEN).transfer(owner(), balance);
            require(status, "Transfer failed");
        }
    }

    /**
     * @dev Withdraw for user (called by SuperCluster)
     */
    function withdrawForUser(uint256 amount) external override {
        require(msg.sender == superClusterAddress, "Only SuperCluster");

        // Withdraw proportionally from adapters
        _withdrawFromAdapters(amount);

        // Transfer to SuperCluster
        bool status = IERC20(TOKEN).transfer(superClusterAddress, amount);
        require(status, "Transfer failed");
    }

    /**
     * @dev Withdraw from adapters proportionally
     */
    function _withdrawFromAdapters(uint256 totalAmount) internal {
        for (uint256 i = 0; i < strategyAdapters.length; i++) {
            address adapter = strategyAdapters[i];
            uint256 allocation = strategyAllocations[i];

            if (allocation > 0 && isActiveAdapter[adapter]) {
                uint256 adapterWithdrawAmount = (totalAmount * allocation) / 10000;

                if (adapterWithdrawAmount > 0) {
                    uint256 sharesToWithdraw = IAdapter(adapter).convertToShares(adapterWithdrawAmount);

                    if (sharesToWithdraw > 0) {
                        IAdapter(adapter).withdraw(sharesToWithdraw);
                    }
                }
            }
        }
    }

    /**
     * @dev Get total value from all adapters + idle funds
     */
    function getTotalValue() external view override returns (uint256) {
        uint256 totalValue = IERC20(TOKEN).balanceOf(address(this)); // Idle funds

        // Add adapter balances
        for (uint256 i = 0; i < strategyAdapters.length; i++) {
            if (isActiveAdapter[strategyAdapters[i]]) {
                totalValue += IAdapter(strategyAdapters[i]).getBalance();
            }
        }

        return totalValue;
    }
}
