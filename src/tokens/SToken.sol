// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SToken is ERC20, Ownable {
    address public underlyingToken;
    uint256 public lastRebaseTime;
    uint256 public rebaseInterval = 1 days;
    uint256 public totalAssetsUnderManagement;

    // Access control
    mapping(address => bool) public authorizedMinters;

    error RebaseNotReady();
    error InvalidUnderlyingToken();
    error UnauthorizedMinter();

    event Rebase(uint256 oldTotalSupply, uint256 newTotalSupply, uint256 assetsPerShare);

    struct STokenConfig {
        string name;
        string symbol;
        address underlyingToken;
    }

    STokenConfig public config;

    constructor(STokenConfig memory config_)
        ERC20(
            string(abi.encodePacked("s", IERC20Metadata(config_.underlyingToken).symbol())),
            string(abi.encodePacked("s", IERC20Metadata(config_.underlyingToken).symbol()))
        )
        Ownable(msg.sender)
    {
        if (config_.underlyingToken == address(0)) revert InvalidUnderlyingToken();
        underlyingToken = config_.underlyingToken;
        config = config_;
        lastRebaseTime = block.timestamp;
    }

    function getRebaseInterval() external view returns (uint256) {
        return rebaseInterval;
    }

    function mint(address to, uint256 amount) external {
        if (!authorizedMinters[msg.sender] && msg.sender != owner()) revert UnauthorizedMinter();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (!authorizedMinters[msg.sender] && msg.sender != owner()) revert UnauthorizedMinter();
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return IERC20Metadata(config.underlyingToken).decimals();
    }

    function rebase() external {
        if (block.timestamp < lastRebaseTime + rebaseInterval) revert RebaseNotReady();

        uint256 oldTotalSupply = totalSupply();
        uint256 newTotalSupply = totalAssetsUnderManagement;

        if (newTotalSupply > oldTotalSupply) {
            // Positive rebase - mint new shares proportionally
            uint256 rebaseAmount = newTotalSupply - oldTotalSupply;
            _mint(address(this), rebaseAmount);
        } else if (newTotalSupply < oldTotalSupply) {
            // Negative rebase - burn shares proportionally
            uint256 burnAmount = oldTotalSupply - newTotalSupply;
            _burn(address(this), burnAmount);
        }

        totalAssetsUnderManagement = newTotalSupply;
        lastRebaseTime = block.timestamp;

        emit Rebase(oldTotalSupply, newTotalSupply, newTotalSupply > 0 ? newTotalSupply / oldTotalSupply : 0);
    }

    function getTotalAssetsUnderManagement() external view returns (uint256) {
        return totalAssetsUnderManagement;
    }

    function updateAssetsUnderManagement(uint256 newAmount) external {
        if (!authorizedMinters[msg.sender] && msg.sender != owner()) revert UnauthorizedMinter();
        totalAssetsUnderManagement = newAmount;
    }

    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        authorizedMinters[minter] = authorized;
    }

    function setUnderlyingToken(address newUnderlyingToken) external onlyOwner {
        if (newUnderlyingToken == address(0)) revert InvalidUnderlyingToken();
        underlyingToken = newUnderlyingToken;
    }
}
