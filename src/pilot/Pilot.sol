// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPilot} from "../interfaces/IPilot.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {AaveAdapter} from "../adapter/AaveAdapter.sol";
import {SuperCluster} from "../SuperCluster.sol";

contract Pilot is IPilot, Ownable {
    using SafeERC20 for IERC20;

    SuperCluster public immutable superCluster;
    IERC20 public immutable underlyingToken;

    // Basic pilot info
    string private _name;
    string private _description;
    address public immutable acceptedToken;
    address public immutable aaveProtocol;

    // Strategy configuration
    IAdapter public aaveAdapter;
    address[] private _adapters;
    uint256[] private _allocations;

    // Events
    event AdapterCreated(address adapter, string strategy);
    event Deposited(address token, uint256 amount);
    event Withdrawn(address token, uint256 amount);
    event RewardsHarvested(uint256 amount);

    // Errors
    error UnsupportedToken();
    error InvalidAmount();
    error AdapterNotInitialized();
    error InsufficientBalance();
    error InvalidStrategy();
    error InvalidAdapterLength();
    error InvalidAllocationLength();
    error AllocationSumError();

    constructor(
        string memory pilotName,
        string memory pilotDescription,
        address _acceptedToken,
        address _underlyingToken,
        address _aaveProtocol,
        address _superCluster
    ) Ownable(msg.sender) {
        _name = pilotName;
        _description = pilotDescription;
        acceptedToken = _acceptedToken;
        underlyingToken = IERC20(_underlyingToken);
        aaveProtocol = _aaveProtocol;
        superCluster = SuperCluster(_superCluster);
        _initializeAdapter();
    }

    function _initializeAdapter() internal {
        require(address(aaveAdapter) == address(0), "Already initialized");
        aaveAdapter = new AaveAdapter(acceptedToken, aaveProtocol, "Aave", _name);
        _adapters = [address(aaveAdapter)];
        _allocations = [10000]; // 100% allocation (basis points)
        emit AdapterCreated(address(aaveAdapter), _name);
    }

    function TOKEN() external view returns (address) {
        return acceptedToken;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function setPilot(string memory newName) external onlyOwner {
        _name = newName;
    }

    function setDescription(string memory newDescription) external onlyOwner {
        _description = newDescription;
    }

    function addAdapter(address /* adapter */ ) external view onlyOwner {
        revert InvalidStrategy(); // This pilot only supports one adapter
    }

    function removeAdapter(address /* adapter */ ) external view onlyOwner {
        revert InvalidStrategy(); // This pilot only supports one adapter
    }

    function isActiveAdapter(address adapter) external view returns (bool) {
        return adapter == address(aaveAdapter);
    }

    function setPilotStrategy(address[] calldata, /* adapters */ uint256[] calldata /* allocations */ )
        external
        view
        onlyOwner
    {
        revert InvalidStrategy(); // This pilot has fixed strategy
    }

    function getStrategy() external view returns (address[] memory adapters, uint256[] memory allocations) {
        return (_adapters, _allocations);
    }

    function invest(uint256 amount, address[] calldata investAdapters, uint256[] calldata /* allocations */ )
        external
    {
        if (investAdapters.length != 1 || investAdapters[0] != address(aaveAdapter)) revert InvalidStrategy();
        if (amount == 0) revert InvalidAmount();

        IERC20(acceptedToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(acceptedToken).approve(address(aaveAdapter), amount);
        aaveAdapter.deposit(amount);
    }

    function divest(uint256 amount, address[] calldata divest_adapters, uint256[] calldata /* _allocations */ )
        external
    {
        if (divest_adapters.length != 1 || divest_adapters[0] != address(aaveAdapter)) revert InvalidStrategy();
        if (amount == 0) revert InvalidAmount();

        uint256 withdrawn = aaveAdapter.withdraw(amount);
        IERC20(acceptedToken).safeTransfer(msg.sender, withdrawn);
    }

    function harvest(address[] calldata adapters) external {
        if (adapters.length != 1 || adapters[0] != address(aaveAdapter)) revert InvalidStrategy();
        uint256 rewards = aaveAdapter.harvest();
        if (rewards > 0) {
            emit RewardsHarvested(rewards);
        }
    }

    function getTotalValue() external view returns (uint256) {
        return aaveAdapter.getBalance();
    }

    function receiveAndInvest(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        // Pull tokens from caller (SuperCluster) into this Pilot contract
        IERC20(acceptedToken).safeTransferFrom(msg.sender, address(this), amount);

        // Approve adapter and deposit
        IERC20(acceptedToken).approve(address(aaveAdapter), amount);
        aaveAdapter.deposit(amount);
    }

    function withdrawForUser(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        uint256 withdrawn = aaveAdapter.withdraw(amount);
        IERC20(acceptedToken).safeTransfer(msg.sender, withdrawn);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 adapterBalance = aaveAdapter.getBalance();
        if (adapterBalance > 0) {
            uint256 withdrawn = aaveAdapter.withdraw(adapterBalance);
            IERC20(acceptedToken).safeTransfer(owner(), withdrawn);
        }
    }

    function redeem(uint256 amount) external override returns (uint256) {
        require(msg.sender == address(superCluster), "Not SuperCluster");
        require(amount > 0, "Zero amount");

        uint256 balance = underlyingToken.balanceOf(address(this));
        require(balance >= amount, "Insufficient funds");

        underlyingToken.transfer(address(superCluster), amount);

        return amount;
    }
}
