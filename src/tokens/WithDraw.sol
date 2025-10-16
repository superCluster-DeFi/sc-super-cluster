// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Withdraw queue manager for SToken -> BaseToken withdrawals
/// @dev Designed to work with your SToken (share-based) and an ERC20 base token.
/// @dev Contract uses SafeERC20 for safe transfers.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SuperCluster} from "../SuperCluster.sol";

interface ISToken {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function burn(address from, uint256 amount) external;
    function allowance(address owner, address spender) external view returns (uint256);
}

/// @title WithdrawManager
/// @notice Minimal queued withdrawal manager: request -> finalize (operator) -> claim (user)
contract Withdraw is Ownable {
    using SafeERC20 for IERC20;

    address public immutable superCluster;

    IERC20 public immutable baseToken; // underlying token (e.g., ETH wrapped or ERC20)
    ISToken public immutable sToken; // rebasing token (sToken)

    uint256 public withdrawDelay; // optional delay (seconds) between request and claim availability
    uint256 public nextRequestId;

    struct Request {
        address user;
        uint256 sAmount; // amount of sToken deposited with request
        uint256 baseAmount; // amount of base token available to claim (set during finalize)
        uint256 requestedAt;
        uint256 availableAt; // when user can claim (0 if not finalized)
        bool finalized;
        bool claimed;
    }

    mapping(uint256 => Request) public requests;

    event WithdrawRequested(uint256 indexed id, address indexed user, uint256 sAmount, uint256 timestamp);
    event WithdrawFinalized(uint256 indexed id, uint256 baseAmount, uint256 availableAt, uint256 timestamp);
    event WithdrawClaimed(uint256 indexed id, address indexed user, uint256 baseAmount, uint256 timestamp);
    event Funded(address indexed sender, uint256 amount, uint256 balance);
    event RequestCancelled(uint256 indexed id, address indexed user, uint256 sAmount);

    constructor(address _sToken, address _baseToken, address _superCluster, uint256 _withdrawDelay)
        Ownable(msg.sender)
    {
        require(_sToken != address(0) && _baseToken != address(0), "Zero address");
        sToken = ISToken(_sToken);
        baseToken = IERC20(_baseToken);
        superCluster = _superCluster;
        withdrawDelay = _withdrawDelay;
        nextRequestId = 1;
    }

    /* ------------------------------------------------------------------------
       User-facing: request withdraw
       ------------------------------------------------------------------------ */

    /// @notice Request a withdrawal by transferring sToken into this contract.
    /// @dev User must approve this contract to spend their sToken before calling.
    function requestWithdraw(uint256 sAmount) external returns (uint256) {
        require(sAmount > 0, "Zero amount");

        // Transfer sToken from user to this contract
        // caller must have approved sToken allowance for this contract
        uint256 allowance = sToken.allowance(msg.sender, address(this));
        require(allowance >= sAmount, "Insufficient allowance for sToken");

        bool ok = sToken.transferFrom(msg.sender, address(this), sAmount);
        require(ok, "sToken transferFrom failed");

        uint256 id = nextRequestId++;
        Request storage r = requests[id];
        r.user = msg.sender;
        r.sAmount = sAmount;
        r.requestedAt = block.timestamp;
        r.finalized = false;
        r.claimed = false;
        r.availableAt = 0;
        r.baseAmount = 0;

        emit WithdrawRequested(id, msg.sender, sAmount, block.timestamp);
        return id;
    }

    function autoRequest(address user, uint256 sAmount) external returns (uint256) {
        require(msg.sender == superCluster, "Only SuperCluster");
        require(sAmount > 0, "Zero amount");

        uint256 id = nextRequestId++;
        Request storage r = requests[id];
        r.user = user;
        r.sAmount = sAmount;
        r.requestedAt = block.timestamp;
        r.finalized = false;
        r.claimed = false;
        r.availableAt = 0;
        r.baseAmount = 0;

        emit WithdrawRequested(id, user, sAmount, block.timestamp);
        return id;
    }

    function requestWithdrawForUser(address user, uint256 sAmount) external returns (uint256) {
        require(msg.sender != address(0), "Invalid sender");
        require(sAmount > 0, "Zero amount");

        // Transfer sToken from SuperCluster to Withdraw contract
        bool ok = sToken.transferFrom(msg.sender, address(this), sAmount);
        require(ok, "sToken transfer failed");

        uint256 id = nextRequestId++;
        Request storage r = requests[id];
        r.user = user;
        r.sAmount = sAmount;
        r.requestedAt = block.timestamp;

        emit WithdrawRequested(id, user, sAmount, block.timestamp);
        return id;
    }

    /// @notice Owner/Operator funds base tokens to this contract to fulfill claims.
    /// @dev Operator should unstake underlying assets off-chain and then call fund() to deposit base tokens for claims.
    function fund(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero fund");
        baseToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount, baseToken.balanceOf(address(this)));
    }

    /// @notice Finalize a pending request by specifying how much base token is available for it.
    /// @dev Finalize marks request as ready to be claimed after optional delay.
    /// @param id request id
    /// @param baseAmount amount of baseToken available for this request (operator determines conversion)
    function finalizeWithdraw(uint256 id, uint256 baseAmount) external onlyOwner {
        Request storage r = requests[id];
        require(r.user != address(0), "Invalid request");
        require(!r.finalized, "Already finalized");
        require(!r.claimed, "Already claimed");
        require(baseAmount > 0, "Zero base amount");

        // Basic safety: ensure contract has enough base tokens to cover
        require(baseToken.balanceOf(address(this)) >= baseAmount, "Insufficient base funds");

        r.baseAmount = baseAmount;
        r.finalized = true;
        r.availableAt = block.timestamp + withdrawDelay;

        emit WithdrawFinalized(id, baseAmount, r.availableAt, block.timestamp);
    }

    /// @notice Cancel request and return sToken to user (only owner/operator can call)
    /// @dev Useful for operator to cancel bad requests or in emergency.
    function cancelRequest(uint256 id) external onlyOwner {
        Request storage r = requests[id];
        require(r.user != address(0), "Invalid request");
        require(!r.claimed, "Already claimed");

        uint256 sAmt = r.sAmount;
        address user = r.user;

        // Reset request
        delete requests[id];

        // Return sToken to user
        // Attempt to transfer stored sToken back
        // Note: transfer may fail if sToken has special logic; assume standard ERC20 transfer works
        // We call sToken.transferFrom? No — we hold sToken in this contract so call baseToken.transfer
        // But ISToken does not expose transfer; to be safe, we use IERC20 interface for sToken raw token address
        IERC20(address(sToken)).safeTransfer(user, sAmt);

        emit RequestCancelled(id, user, sAmt);
    }

    /* ------------------------------------------------------------------------
       User: claim finalized withdraw
       ------------------------------------------------------------------------ */

    /// @notice Claim finalized withdraw after operator marked it ready and optional delay passed
    function claim(uint256 id) external {
        Request storage r = requests[id];
        require(r.user != address(0), "Invalid request");
        require(!r.claimed, "Already claimed");
        require(r.finalized, "Not finalized yet");
        require(block.timestamp >= r.availableAt, "Not available yet");
        require(msg.sender == r.user, "Not request owner");

        uint256 baseAmount = r.baseAmount;
        require(baseAmount > 0, "Zero base amount");

        // mark claimed before external transfer to avoid reentrancy
        r.claimed = true;

        // Burn held sToken to update SToken state (requires this contract to be authorized minter)
        // If burn call fails (not authorized), we still proceed but sTokens remain in this contract;
        // it's recommended to set this contract as authorized minter on SToken so burn reduces total AUM.
        try ISToken(address(sToken)).burn(address(this), r.sAmount) {
            // burned successfully
        } catch {
            // ignore: fallback to not burning if not allowed
        }

        // Transfer base token to user
        baseToken.safeTransfer(r.user, baseAmount);

        emit WithdrawClaimed(id, r.user, baseAmount, block.timestamp);
    }

    /* ------------------------------------------------------------------------
       Views / helpers
       ------------------------------------------------------------------------ */

    function getRequest(uint256 id)
        external
        view
        returns (
            address user,
            uint256 sAmount,
            uint256 baseAmount,
            uint256 requestedAt,
            uint256 availableAt,
            bool finalized,
            bool claimed
        )
    {
        Request storage r = requests[id];
        return (r.user, r.sAmount, r.baseAmount, r.requestedAt, r.availableAt, r.finalized, r.claimed);
    }

    function contractBaseBalance() external view returns (uint256) {
        return baseToken.balanceOf(address(this));
    }

    function contractSTokenBalance() external view returns (uint256) {
        return IERC20(address(sToken)).balanceOf(address(this));
    }

    /* ------------------------------------------------------------------------
       Owner utilities
       ------------------------------------------------------------------------ */

    function setWithdrawDelay(uint256 _delay) external onlyOwner {
        withdrawDelay = _delay;
    }

    /// @notice Emergency withdraw of base tokens to owner
    function emergencyWithdrawBase(uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Invalid to");
        baseToken.safeTransfer(to, amount);
    }

    /// @notice Emergency withdraw of sTokens to owner (could be used for migration)
    function emergencyWithdrawSToken(uint256 amount, address to) external onlyOwner {
        require(to != address(0), "Invalid to");
        IERC20(address(sToken)).safeTransfer(to, amount);
    }
}
