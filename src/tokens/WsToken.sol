// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SToken} from "./SToken.sol";

contract WsToken is ERC20 {
    address public immutable STOKEN;
    IERC20 public immutable STOKENCONTRACT;
    SToken public immutable STOKENINSTANCE;

    // Track total STOKEN deposited (not affected by rebases)
    uint256 public totalSTokenDeposited;

    event Wrapped(address indexed user, uint256 sTokenAmount, uint256 wsTokenAmount);
    event Unwrapped(address indexed user, uint256 wsTokenAmount, uint256 sTokenAmount);

    constructor(address _sToken)
        ERC20(
            string(abi.encodePacked("w", IERC20Metadata(_sToken).symbol())),
            string(abi.encodePacked("w", IERC20Metadata(_sToken).symbol()))
        )
    {
        STOKEN = _sToken;
        STOKENCONTRACT = IERC20(_sToken);
        STOKENINSTANCE = SToken(_sToken);
    }

    /**
     * @dev Wrap STOKEN to wsToken
     * User must first approve this contract to spend their STOKEN
     * The conversion rate accounts for rebases that may have occurred
     */
    function wrap(uint256 sTokenAmount) external {
        require(sTokenAmount > 0, "Amount must be greater than 0");
        require(STOKENCONTRACT.balanceOf(msg.sender) >= sTokenAmount, "Insufficient STOKEN balance");

        // Calculate wsToken amount based on current exchange rate
        uint256 wsTokenAmount = sTokenToWsToken(sTokenAmount);
        require(wsTokenAmount > 0, "wsToken amount too small");

        // Transfer STOKEN from user to this contract
        STOKENCONTRACT.transferFrom(msg.sender, address(this), sTokenAmount);

        // Update total deposited (this tracks the actual STOKEN deposited, not affected by rebases)
        totalSTokenDeposited += sTokenAmount;

        // Mint wsToken to user
        _mint(msg.sender, wsTokenAmount);

        emit Wrapped(msg.sender, sTokenAmount, wsTokenAmount);
    }

    /**
     * @dev Unwrap wsToken back to STOKEN
     * The conversion rate accounts for rebases that may have occurred
     */
    function unwrap(uint256 wsTokenAmount) external {
        require(wsTokenAmount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= wsTokenAmount, "Insufficient wsToken balance");

        // Calculate STOKEN amount based on current exchange rate
        uint256 sTokenAmount = wsTokenToSToken(wsTokenAmount);
        require(STOKENCONTRACT.balanceOf(address(this)) >= sTokenAmount, "Insufficient STOKEN in contract");

        // Burn wsToken from user
        _burn(msg.sender, wsTokenAmount);

        // Update total deposited
        totalSTokenDeposited -= sTokenAmount;

        // Transfer STOKEN back to user
        STOKENCONTRACT.transfer(msg.sender, sTokenAmount);

        emit Unwrapped(msg.sender, wsTokenAmount, sTokenAmount);
    }

    /**
     * @dev Convert STOKEN amount to wsToken amount
     * This accounts for rebases that may have occurred since deposits
     */
    function sTokenToWsToken(uint256 sTokenAmount) public view returns (uint256) {
        if (totalSupply() == 0 || totalSTokenDeposited == 0) {
            // First deposit: 1:1 ratio
            return sTokenAmount;
        }

        // Calculate current exchange rate based on rebases
        // wsToken amount = (STOKEN amount * total wsToken supply) / total STOKEN deposited
        return (sTokenAmount * totalSupply()) / totalSTokenDeposited;
    }

    /**
     * @dev Convert wsToken amount to STOKEN amount
     * This accounts for rebases that may have occurred since deposits
     */
    function wsTokenToSToken(uint256 wsTokenAmount) public view returns (uint256) {
        if (totalSupply() == 0 || totalSTokenDeposited == 0) {
            // No deposits yet
            return 0;
        }

        // Calculate current exchange rate based on rebases
        // STOKEN amount = (wsToken amount * total STOKEN deposited) / total wsToken supply
        return (wsTokenAmount * totalSTokenDeposited) / totalSupply();
    }

    /**
     * @dev Get the underlying STOKEN balance held by this contract
     */
    function getSTokenBalance() external view returns (uint256) {
        return STOKENCONTRACT.balanceOf(address(this));
    }

    /**
     * @dev Get the current exchange rate (STOKEN per wsToken)
     */
    function getExchangeRate() external view returns (uint256) {
        if (totalSupply() == 0) {
            return 1e18; // 1:1 if no wsToken exists
        }
        return (totalSTokenDeposited * 1e18) / totalSupply();
    }

    /**
     * @dev Get the total STOKEN deposited (not affected by rebases)
     */
    function getTotalSTokenDeposited() external view returns (uint256) {
        return totalSTokenDeposited;
    }
}
