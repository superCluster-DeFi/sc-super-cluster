// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Adapter
 * @dev Base adapter contract with real protocol query patterns
 */
abstract contract Adapter is IAdapter, Ownable, ReentrancyGuard {
    address public immutable TOKEN;
    address public immutable PROTOCOL_ADDRESS;
    string public protocolName;
    string public pilotStrategy;
    bool public isActive;
    uint256 public totalDeposited;

    // Events
    event AdapterActivated();
    event AdapterDeactivated();
    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);

    // Errors
    error AdapterNotActive();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyActive() {
        if (!isActive) revert AdapterNotActive();
        _;
    }

    constructor(address _token, address _protocolAddress, string memory _protocolName, string memory _protocolStrategy)
        Ownable(msg.sender)
    {
        TOKEN = _token;
        PROTOCOL_ADDRESS = _protocolAddress;
        protocolName = _protocolName;
        pilotStrategy = _protocolStrategy;
        isActive = true;
    }

    /**
     * @dev Get balance from protocol (implemented by child contracts)
     */
    function getBalance() external view virtual override returns (uint256);

    /**
     * @dev Update internal tracking
     */
    function _updateTotalDeposited(uint256 amount, bool isDeposit) internal {
        if (isDeposit) {
            totalDeposited += amount;
        } else {
            totalDeposited = totalDeposited >= amount ? totalDeposited - amount : 0;
        }
    }

    /**
     * @dev Get protocol name
     */
    function getProtocolName() external view override returns (string memory) {
        return protocolName;
    }

    /**
     * @dev Get protocol address
     */
    function getProtocolAddress() external view override returns (address) {
        return PROTOCOL_ADDRESS;
    }

    function getPilotStrategy() external view override returns (string memory) {
        return pilotStrategy;
    }

    /**
     * @dev Activate the adapter
     */
    function activate() external onlyOwner {
        isActive = true;
        emit AdapterActivated();
    }

    /**
     * @dev Deactivate the adapter
     */
    function deactivate() external onlyOwner {
        isActive = false;
        emit AdapterDeactivated();
    }
}
