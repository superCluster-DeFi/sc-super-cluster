// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Adapter
 * @dev Base adapter contract that other adapters can inherit from
 */
abstract contract Adapter is IAdapter, Ownable, ReentrancyGuard {
    address public immutable IDRX;
    address public immutable PROTOCOL_ADDRESS;
    string public protocolName;
    string public pilotStrategy;
    bool public isActive;

    // Events
    event AdapterActivated();
    event AdapterDeactivated();

    // Errors
    error AdapterNotActive();
    error InvalidAmount();
    error InsufficientBalance();

    modifier onlyActive() {
        if (!isActive) revert AdapterNotActive();
        _;
    }

    constructor(address _idrx, address _protocolAddress, string memory _protocolName, string memory _protocolStrategy)
        Ownable(msg.sender)
    {
        IDRX = _idrx;
        PROTOCOL_ADDRESS = _protocolAddress;
        protocolName = _protocolName;
        pilotStrategy = _protocolStrategy;
        isActive = true;
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
}
