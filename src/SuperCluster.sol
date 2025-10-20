// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SToken} from "./tokens/SToken.sol";
import {IPilot} from "./interfaces/IPilot.sol";
import {WsToken} from "./tokens/WsToken.sol";
import {Withdraw} from "./tokens/WithDraw.sol";
import {console} from "forge-std/console.sol";

contract SuperCluster is Ownable, ReentrancyGuard {
    SToken public sToken; // SToken token (rebasing)
    mapping(address => bool) public supportedTokens;
    mapping(address => uint256) public tokenBalances;

    WsToken public wsToken; // Wrapped SToken (non-rebasing)

    // Withdraw manager
    Withdraw public withdrawManager;

    // Pilot management
    mapping(address => bool) public registeredPilots;
    address[] public pilots;

    // Events
    event PilotRegistered(address indexed pilot);
    event TokenDeposited(address indexed token, address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed user, uint256 amount, uint256 requestId);
    event TokenSupported(address indexed token, bool supported);
    event PilotSelected(address indexed pilot, address indexed token, uint256 amount);

    // Errors
    error PilotNotRegistered();
    error PilotAlreadyRegistered();
    error InsufficientBalance();
    error TransferFailed();
    error TokenNotSupported();
    error AmountMustBeGreaterThanZero();

    constructor(address underlyingToken_) Ownable(msg.sender) {
        // Get token metadata from the underlying token
        IERC20Metadata tokenMetadata = IERC20Metadata(underlyingToken_);
        string memory tokenName = tokenMetadata.name();
        string memory tokenSymbol = tokenMetadata.symbol();

        // Deploy sToken with dynamic name and symbol
        sToken = new SToken(
            string(abi.encodePacked("s", tokenName)), string(abi.encodePacked("s", tokenSymbol)), underlyingToken_
        );

        // Deploy wsToken (wrapped sToken)
        wsToken = new WsToken(
            string(abi.encodePacked("ws", tokenName)), string(abi.encodePacked("ws", tokenSymbol)), underlyingToken_
        );

        // Delay Withdraw
        withdrawManager = new Withdraw(address(sToken), underlyingToken_, address(this), 0);

        // Set this contract as authorized minter for the sToken
        sToken.setAuthorizedMinter(address(this), true);
        wsToken.setAuthorizedMinter(address(this), true);

        // Add supported tokens
        supportedTokens[underlyingToken_] = true;
    }

    /**
     * @dev Trigger WsToken wrap for user (internal)
     */
    function autoWrap(address user, uint256 sAmount) internal {
        uint256 beforeBalance = wsToken.balanceOf(address(this));

        IERC20(address(sToken)).approve(address(wsToken), sAmount);

        wsToken.wrap(sAmount);

        uint256 afterBalance = wsToken.balanceOf(address(this));
        uint256 minted = afterBalance - beforeBalance; // Calculate minted wsToken

        wsToken.transfer(user, minted);
    }

    /**
     * @dev Trigger rebase on the underlying sToken by calculating current AUM
     */
    function rebase() external {
        uint256 newAUM = calculateTotalAUM();
        sToken.rebase(newAUM);
    }

    /**
     * @dev Manual rebase with specific AUM (for testing/admin)
     */
    function rebaseWithAUM(uint256 newAUM) external onlyOwner {
        sToken.rebase(newAUM);
    }

    /**
     * @dev Calculate total Assets Under Management across all pilots
     */
    function calculateTotalAUM() public view returns (uint256) {
        uint256 totalAUM = 0;

        //  Check actual token balance in contract
        totalAUM += IERC20(address(sToken)).balanceOf(address(this));

        // Add assets managed by all pilots
        for (uint256 i = 0; i < pilots.length; i++) {
            totalAUM += IPilot(pilots[i]).getTotalValue();
        }

        return totalAUM;
    }

    /**
     * @dev Universal deposit function for any supported token
     */
    function deposit(address pilot, address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!registeredPilots[pilot]) revert PilotNotRegistered();
        if (!supportedTokens[token]) revert TokenNotSupported();

        // Transfer token dari user ke SuperCluster
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Mint sToken ke user
        sToken.mint(msg.sender, amount);

        // Approve pilot for token transfer
        IERC20(token).approve(pilot, amount);

        // Deposit to pilot
        IPilot(pilot).receiveAndInvest(amount);

        // Update AUM
        uint256 totalAUM = calculateTotalAUM();
        sToken.updateAssetsUnderManagement(totalAUM);

        emit TokenDeposited(token, msg.sender, amount);
        emit PilotSelected(pilot, token, amount);
    }

    /**
     * @dev Universal withdraw function for any supported token
     */
    function withdraw(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (sToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Burn user's sToken
        sToken.burn(msg.sender, amount);

        // Update AUM setelah burn
        sToken.updateAssetsUnderManagement(sToken.totalSupply());

        // Buat request withdraw di WithdrawManager
        uint256 requestId = withdrawManager.autoRequest(msg.sender, amount);

        emit TokenWithdrawn(token, msg.sender, amount, requestId);
    }

    function finalizeWithdraw(uint256 requestId, uint256 baseAmount) external onlyOwner nonReentrant {
        uint256 managerBalance = withdrawManager.contractBaseBalance();
        require(managerBalance >= baseAmount, "WithdrawManager: insufficient base balance");

        withdrawManager.finalizeWithdraw(requestId, baseAmount);

        uint256 totalAUM = calculateTotalAUM();
        sToken.updateAssetsUnderManagement(totalAUM);
    }

    // call function in withdraw manager to claim withdrawn tokens
    function claim(uint256 requestId) external nonReentrant {
        withdrawManager.claim(requestId);
    }

    /**
     * @dev Get all registered pilots
     */
    function getPilots() external view returns (address[] memory) {
        return pilots;
    }

    /**
     * @dev Register a new pilot (only owner)
     */
    function registerPilot(address pilot, address acceptedToken) external onlyOwner {
        require(!registeredPilots[pilot], "Pilot already registered");

        registeredPilots[pilot] = true;
        pilots.push(pilot);
        supportedTokens[acceptedToken] = true;

        emit PilotRegistered(pilot);
    }

    function setWithdrawManager(address _manager) external onlyOwner {
        require(_manager != address(0), "Zero manager");
        withdrawManager = Withdraw(_manager);
    }
}
