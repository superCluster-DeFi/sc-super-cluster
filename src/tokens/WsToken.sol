// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WsToken (wrapped sToken)
 * @notice Wrapped version of a rebasing STOKEN. This contract mints a non-rebasing wrapped token (wsToken)
 *         where the conversion rate is derived from the actual STOKEN balance held by this contract.
 *
 * Design notes:
 *  - We use the contract's STOKEN balance (which increases with rebases) to determine conversion rate.
 *  - This matches the wstETH pattern: wsToken supply is fixed per holder, while each wsToken represents an
 *    increasing amount of STOKEN as rebases happen.
 */
contract WsToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable STOKENCONTRACT;
    // optional reference if you have a specific SToken interface with extra functions
    // kept out for minimal dependency; if needed, you can cast to your SToken type
    mapping(address => bool) public authorizedMinters;

    // Events
    event Wrapped(address indexed user, uint256 sTokenAmount, uint256 wsTokenAmount);
    event Unwrapped(address indexed user, uint256 wsTokenAmount, uint256 sTokenAmount);

    /**
     * @param _sToken address of the rebasing token (e.g. sToken / stETH)
     */
    constructor(string memory _name, string memory _symbol, address _sToken)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
    {
        require(_sToken != address(0), "underlying zero");
        STOKENCONTRACT = IERC20(_sToken);
    }

    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        authorizedMinters[minter] = authorized;
    }

    /**
     * @notice Wrap a given amount of STOKEN and receive wsToken
     * @dev User must approve this contract to spend sTokenAmount beforehand.
     *      Conversion uses current STOKEN balance in this contract.
     * @param sTokenAmount amount of STOKEN to wrap
     */
    function wrap(uint256 sTokenAmount) external {
        require(sTokenAmount > 0, "Amount must be > 0");

        // Get current STOKEN balance held by this contract (includes rebases) same underlying token
        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        // Transfer STOKEN from the caller into this contract
        // Using SafeERC20 to support tokens that don't return bool
        STOKENCONTRACT.safeTransferFrom(msg.sender, address(this), sTokenAmount);

        uint256 wsTokenAmount;
        if (_totalSupply == 0 || stTokenBalance == 0) {
            // first deposit (or previous balance zero): mint 1:1
            wsTokenAmount = sTokenAmount;
        } else {
            // wsToken = sTokenAmount * totalSupply / stTokenBalance
            // Use the pre-transfer stTokenBalance OR newStTokenBalance - sTokenAmount both are valid;
            // using stTokenBalance (pre-transfer) keeps same ratio as other deposits in the same tx ordering.
            wsTokenAmount = (sTokenAmount * _totalSupply) / stTokenBalance;
            require(wsTokenAmount > 0, "wsToken amount too small");
        }

        // Mint wsToken to user
        _mint(msg.sender, wsTokenAmount);

        emit Wrapped(msg.sender, sTokenAmount, wsTokenAmount);
    }

    /**
     * @notice Unwrap wsToken to receive underlying STOKEN
     * @param wsTokenAmount amount of wsToken to burn
     */
    function unwrap(uint256 wsTokenAmount) external {
        require(wsTokenAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= wsTokenAmount, "Insufficient wsToken balance");

        uint256 _totalSupply = totalSupply();
        require(_totalSupply > 0, "Total supply zero");

        // Current STOKEN balance (includes rebases)
        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        require(stTokenBalance > 0, "No STOKEN in contract");

        // sTokenAmount = wsTokenAmount * stTokenBalance / totalSupply
        uint256 sTokenAmount = (wsTokenAmount * stTokenBalance) / _totalSupply;
        require(sTokenAmount > 0, "sToken amount too small");

        // Burn wsToken from user
        _burn(msg.sender, wsTokenAmount);

        // Transfer underlying STOKEN to user
        STOKENCONTRACT.safeTransfer(msg.sender, sTokenAmount);

        emit Unwrapped(msg.sender, wsTokenAmount, sTokenAmount);
    }

    /**
     * @notice Unwrap and send STOKEN to a recipient
     * @param wsTokenAmount amount of wsToken to burn
     * @param recipient address to receive STOKEN
     */
    function unwrapTo(uint256 wsTokenAmount, address recipient) external {
        require(recipient != address(0), "Recipient zero");
        require(wsTokenAmount > 0, "Amount must be > 0");

        uint256 _totalSupply = totalSupply();
        require(_totalSupply > 0, "Total supply zero");

        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        require(stTokenBalance > 0, "No STOKEN in contract");

        uint256 sTokenAmount = (wsTokenAmount * stTokenBalance) / _totalSupply;
        require(sTokenAmount > 0, "sToken amount too small");

        _burn(msg.sender, wsTokenAmount);
        STOKENCONTRACT.safeTransfer(recipient, sTokenAmount);

        emit Unwrapped(recipient, wsTokenAmount, sTokenAmount);
    }

    /* --------------------------------------------------------------------
       Helper / view functions
       -------------------------------------------------------------------- */

    /**
     * @notice Returns how many STOKEN one wsToken is worth (scaled by 1e18)
     * @dev stPerWs = stTokenBalance * 1e18 / totalSupply
     */
    function stTokenPerWsToken() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 1e18; // 1:1 initially
        }
        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        return (stTokenBalance * 1e18) / _totalSupply;
    }

    /**
     * @notice Returns how many wsToken equals one STOKEN (scaled by 1e18)
     * @dev wsPerSt = totalSupply * 1e18 / stTokenBalance
     */
    function wsTokenPerStToken() public view returns (uint256) {
        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        uint256 _totalSupply = totalSupply();
        if (stTokenBalance == 0) {
            return 1e18;
        }
        return (_totalSupply * 1e18) / stTokenBalance;
    }

    /**
     * @notice Convert STOKEN amount to wsToken amount using current rate
     */
    function sTokenToWsToken(uint256 sTokenAmount) external view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        if (_totalSupply == 0 || stTokenBalance == 0) {
            return sTokenAmount;
        }
        return (sTokenAmount * _totalSupply) / stTokenBalance;
    }

    /**
     * @notice Convert wsToken amount to STOKEN amount using current rate
     */
    function wsTokenToSToken(uint256 wsTokenAmount) external view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        uint256 stTokenBalance = STOKENCONTRACT.balanceOf(address(this));
        if (_totalSupply == 0 || stTokenBalance == 0) {
            return 0;
        }
        return (wsTokenAmount * stTokenBalance) / _totalSupply;
    }

    /**
     * @notice Returns current STOKEN balance held by this contract
     */
    function getSTokenBalance() external view returns (uint256) {
        return STOKENCONTRACT.balanceOf(address(this));
    }
}
