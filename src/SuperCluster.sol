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

    mapping(address => string) public userStrategy;
    mapping(string => address) public strategyToPilot;

    // Events
    event PilotRegistered(address indexed pilot);
    event TokenDeposited(address indexed token, address indexed user, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed user, uint256 amount);
    event TokenSupported(address indexed token, bool supported);
    event PilotSelected(address indexed pilot, address indexed token, uint256 amount);

    // Errors
    error PilotNotRegistered();
    error PilotAlreadyRegistered();
    error InsufficientBalance();
    error TransferFailed();
    error TokenNotSupported();
    error AmountMustBeGreaterThanZero();

    constructor(address underlyingToken_, address sTokenAddr, address wsTokenAddr, address withdrawManagerAddr)
        Ownable(msg.sender)
    {
        // Use pre-deployed token & manager addresses to avoid embedding large initcode
        sToken = SToken(sTokenAddr);
        wsToken = WsToken(wsTokenAddr);
        withdrawManager = Withdraw(withdrawManagerAddr);

        // Register supported underlying token
        supportedTokens[underlyingToken_] = true;
    }

    function registerStrategy(string calldata strategy, address pilot) external onlyOwner {
        require(pilot != address(0), "Zero pilot address");
        strategyToPilot[strategy] = pilot;
    }

    function selectStrategy(string calldata strategy) external {
        require(strategyToPilot[strategy] != address(0), "Strategy not registered");
        address oldPilot = strategyToPilot[userStrategy[msg.sender]];
        address newPilot = strategyToPilot[strategy];

        // If user has funds and is changing pilots, move them
        if (oldPilot != address(0) && oldPilot != newPilot) {
            uint256 pilotBalance = IERC20(address(sToken)).balanceOf(msg.sender);
            if (pilotBalance > 0) {
                // Redeem from old pilot
                uint256 redeemed = IPilot(oldPilot).redeem(pilotBalance);

                // Invest in new pilot
                IERC20(address(sToken)).approve(newPilot, redeemed);
                IPilot(newPilot).receiveAndInvest(redeemed);
            }
        }

        userStrategy[msg.sender] = strategy;
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
    function deposit(address token, uint256 amount) external {
        require(bytes(userStrategy[msg.sender]).length > 0, "Strategy not selected");
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();

        address pilotAddress = strategyToPilot[userStrategy[msg.sender]];
        require(pilotAddress != address(0), "Pilot not found");

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        require(success, "Transfer failed");

        // Keep funds in SuperCluster until user selects a pilot
        sToken.mint(msg.sender, amount);
        sToken.updateAssetsUnderManagement(sToken.totalSupply());

        // Update internal accounting of deposited base tokens
        tokenBalances[token] += amount;

        emit TokenDeposited(token, msg.sender, amount);
    }

    /**
     * @dev Universal withdraw function for any supported token
     */
    function withdraw(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (sToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // 1. Burn sToken from user
        sToken.burn(msg.sender, amount);

        // 2. Mint equivalent sToken to the Withdraw manager (so it holds the sToken)
        require(address(withdrawManager) != address(0), "Withdraw manager not set");
        sToken.mint(address(withdrawManager), amount);

        // 3. Update AUM after mint/burn
        sToken.updateAssetsUnderManagement(sToken.totalSupply());

        // 4. Notify withdraw manager to create a request
        withdrawManager.autoRequest(msg.sender, amount);

        emit TokenWithdrawn(token, msg.sender, amount);
    }

    /**
     * @dev User selects a pilot for their funds using any supported token
     */
    function selectPilot(address pilot, address token, uint256 amount) external {
        if (!registeredPilots[pilot]) revert PilotNotRegistered();
        if (amount == 0) revert AmountMustBeGreaterThanZero();
        if (!supportedTokens[token]) revert TokenNotSupported();
        if (tokenBalances[token] < amount) revert InsufficientBalance();
        if (sToken.balanceOf(msg.sender) < amount) revert InsufficientBalance();

        // Update token balance
        tokenBalances[token] -= amount;

        // Burn sToken from user and update assets under management
        sToken.burn(msg.sender, amount);
        bool status = IERC20(token).transfer(pilot, amount);
        require(status, "Transfer failed");

        emit PilotSelected(pilot, token, amount);
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
