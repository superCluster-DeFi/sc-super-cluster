// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract SToken is IERC20, IERC20Metadata, Ownable {
    string public name;
    string public symbol;
    uint8 public decimals;
    address public underlyingToken;
    uint256 public lastRebaseTime;
    uint256 public rebaseInterval = 1 days;
    uint256 public totalAssetsUnderManagement;


    using SafeERC20 for IERC20;

    IERC20 public immutable baseToken;

   

    // Mapping of share balances (tidak berubah saat rebase)
    mapping(address => uint256) private _shareBalances;
    uint256 private _totalShares;

    // ERC20 allowances
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) public authorizedMinters;

    event Rebase(uint256 oldAUM, uint256 newAUM, uint256 sharePrice, uint256 timestamp);

    modifier canRebase() {
        require(block.timestamp >= lastRebaseTime + rebaseInterval, "Rebase not ready yet");
        _;
    }

    constructor(string memory _name, string memory _symbol, address _underlyingToken, address _baseToken) Ownable(msg.sender) {
        name = _name;
        symbol = _symbol;
        underlyingToken = _underlyingToken;
        decimals = IERC20Metadata(_underlyingToken).decimals();
        baseToken = IERC20(_baseToken);
    
        lastRebaseTime = block.timestamp;
    }

    function balanceOf(address account) public view returns (uint256) {
        if (_totalShares == 0) return 0;
        // Balance = (user shares / total shares) × total AUM
        return (_shareBalances[account] * totalAssetsUnderManagement) / _totalShares;
    }

    function totalSupply() public view returns (uint256) {
        return totalAssetsUnderManagement;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");

        _transfer(from, to, amount);
        _approve(from, msg.sender, currentAllowance - amount);

        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = balanceOf(from);
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");

        // Calculate shares to transfer based on amount
        uint256 sharesToTransfer = (amount * _shareBalances[from]) / fromBalance;

        _shareBalances[from] -= sharesToTransfer;
        _shareBalances[to] += sharesToTransfer;

        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function updateAssetsUnderManagement(uint256 newAmount) external {
        require(authorizedMinters[msg.sender] || msg.sender == owner(), "Unauthorized");
        totalAssetsUnderManagement = newAmount;
    }

    function mint(address to, uint256 amount) external {
        require(authorizedMinters[msg.sender] || msg.sender == owner(), "Unauthorized");

        uint256 shares;
        if (_totalShares == 0) {
            shares = amount; // Initial mint: 1:1 ratio
        } else {
            // shares = amount × total shares / total AUM
            shares = (amount * _totalShares) / totalAssetsUnderManagement;
        }

        _shareBalances[to] += shares;
        _totalShares += shares;
        totalAssetsUnderManagement += amount;

        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(authorizedMinters[msg.sender] || msg.sender == owner(), "Unauthorized");

        uint256 userBalance = balanceOf(from);
        require(userBalance >= amount, "Insufficient balance");

        // Calculate shares to burn
        uint256 sharesToBurn = (amount * _shareBalances[from]) / userBalance;

        _shareBalances[from] -= sharesToBurn;
        _totalShares -= sharesToBurn;
        totalAssetsUnderManagement -= amount;

        emit Transfer(from, address(0), amount);
    }

    function _mintShares(address to, uint256 amount) internal {
        uint256 shares;
        if (_totalShares == 0) {
            shares = amount; // 1:1 ratio at start
        } else {
            shares = (amount * _totalShares) / totalAssetsUnderManagement;
        }

        _shareBalances[to] += shares;
        _totalShares += shares;
        totalAssetsUnderManagement += amount;

        emit Transfer(address(0), to, amount);
    }


    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        authorizedMinters[minter] = authorized;
    }

    // Helper functions for shares
    function sharesOf(address account) external view returns (uint256) {
        return _shareBalances[account];
    }

    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    function getTotalAssetsUnderManagement() external view returns (uint256) {
        return totalAssetsUnderManagement;
    }

   function stake(uint256 amount) external {
        require(amount > 0, "Zero stake");
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        _mintShares(msg.sender, amount);
    }

    function totalBase() external view returns (uint256) {
        return baseToken.balanceOf(address(this));
    }

    function rebase(uint256 newAUM) external canRebase {
        require(authorizedMinters[msg.sender] || msg.sender == owner(), "Unauthorized");

        uint256 oldAUM = totalAssetsUnderManagement;
        totalAssetsUnderManagement = newAUM;

        //  Set last rebase time
        lastRebaseTime = block.timestamp;

        uint256 sharePrice = _totalShares > 0 ? newAUM * 1e18 / _totalShares : 0;

        emit Rebase(oldAUM, newAUM, sharePrice, block.timestamp);
    }

    function forceRebase(uint256 newAUM) external onlyOwner {
        uint256 oldAUM = totalAssetsUnderManagement;
        totalAssetsUnderManagement = newAUM;
        lastRebaseTime = block.timestamp;

        uint256 sharePrice = _totalShares > 0 ? newAUM * 1e18 / _totalShares : 0;

        emit Rebase(oldAUM, newAUM, sharePrice, block.timestamp);
    }

    function isRebaseReady() external view returns (bool) {
        return block.timestamp >= lastRebaseTime + rebaseInterval;
    }

    function timeUntilNextRebase() external view returns (uint256) {
        uint256 nextRebaseTime = lastRebaseTime + rebaseInterval;
        if (block.timestamp >= nextRebaseTime) {
            return 0;
        }
        return nextRebaseTime - block.timestamp;
    }

    function setRebaseInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Interval must be greater than 0");
        rebaseInterval = newInterval;
    }
}
