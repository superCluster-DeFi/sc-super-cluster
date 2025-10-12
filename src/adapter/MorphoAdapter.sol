// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Adapter} from "../adapter/Adapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Id, MarketParams, Position} from "../mocks/interfaces/IMorpho.sol";

interface IMockMorpho {
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256);

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);

    function position(Id id, address user) external view returns (uint128, uint128, uint128);

    function market(Id id) external view returns (uint128, uint128, uint128, uint128, uint128, uint128);

    function createMarket(MarketParams memory marketParams) external;

    function enableIrm(address irm) external;

    function enableLltv(uint256 lltv) external;

    function accrueInterest(MarketParams memory marketParams) external;

    function idToMarketParams(Id id) external view returns (MarketParams memory);
}

contract MorphoAdapter is Adapter {
    IMockMorpho public immutable MORPHO;
    MarketParams public marketParams;
    Id public marketId;

    constructor(
        address _token,
        address _morpho,
        MarketParams memory _marketParams,
        string memory _protocolName,
        string memory _pilotStrategy
    ) Adapter(_token, _morpho, _protocolName, _pilotStrategy) {
        MORPHO = IMockMorpho(_morpho);
        marketParams = _marketParams;
        marketId = Id.wrap(keccak256(abi.encode(_marketParams)));
    }

    /**
     * @dev  Supply to your MockMorpho
     */
    function deposit(uint256 amount) external override onlyActive returns (uint256 shares) {
        if (amount == 0) revert InvalidAmount();

        // Transfer from caller (Pilot)
        bool status = IERC20(TOKEN).transferFrom(msg.sender, address(this), amount);
        require(status, "Transfer failed");

        // Approve MockMorpho
        IERC20(TOKEN).approve(address(MORPHO), amount);

        // Supply to MockMorpho - your real implementation
        (uint256 assetsSupplied, uint256 sharesReturned) = MORPHO.supply(
            marketParams,
            amount, // assets to supply
            0, // shares (0 = supply by assets)
            address(this), // onBehalf (this adapter)
            "" // data (empty)
        );

        // Update internal tracking
        _updateTotalDeposited(assetsSupplied, true);

        emit Deposited(assetsSupplied);
        return sharesReturned;
    }

    /**
     * @dev  Withdraw from your MockMorpho
     */
    function withdraw(uint256 shares) external override onlyActive returns (uint256 amount) {
        if (shares == 0) revert InvalidAmount();

        // Check current position
        (uint128 supplyShares,,) = MORPHO.position(marketId, address(this));

        if (uint256(supplyShares) < shares) revert InsufficientBalance();

        // Withdraw from MockMorpho - your real implementation
        (uint256 assetsWithdrawn,) = MORPHO.withdraw(
            marketParams,
            0, // assets (0 = withdraw by shares)
            shares, // shares to withdraw
            address(this), // onBehalf (this adapter)
            msg.sender // receiver (send to caller)
        );

        // Update internal tracking
        _updateTotalDeposited(assetsWithdrawn, false);

        emit Withdrawn(assetsWithdrawn);
        return assetsWithdrawn;
    }

    /**
     * @dev  Get current supply position
     */
    function getBalance() external view override returns (uint256) {
        (uint128 supplyShares,,) = MORPHO.position(marketId, address(this));

        // Convert shares to assets
        (uint128 totalSupplyAssets, uint128 totalSupplyShares,,,,) = MORPHO.market(marketId);

        if (totalSupplyShares == 0) return 0;

        // Calculate: userShares * totalAssets / totalShares
        return (uint256(supplyShares) * uint256(totalSupplyAssets)) / uint256(totalSupplyShares);
    }

    /**
     * @dev  Get raw shares
     */
    function getSupplyShares() external view returns (uint256) {
        (uint128 supplyShares,,) = MORPHO.position(marketId, address(this));
        return uint256(supplyShares);
    }

    /**
     * @dev  Get full position data
     */
    function getPosition() external view returns (uint128 supplyShares, uint128 borrowShares, uint128 collateral) {
        return MORPHO.position(marketId, address(this));
    }

    /**
     * @dev ✅Get market information
     */
    function getMarketData()
        external
        view
        returns (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            uint128 lastUpdate,
            uint128 fee
        )
    {
        return MORPHO.market(marketId);
    }

    /**
     * @dev Convert assets to shares using current rate
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        if (assets == 0) return 0;

        (uint128 totalSupplyAssets, uint128 totalSupplyShares,,,,) = MORPHO.market(marketId);

        if (totalSupplyAssets == 0 || totalSupplyShares == 0) {
            return assets; // 1:1 if no existing supply
        }

        // Calculate: assets * totalShares / totalAssets
        return (assets * uint256(totalSupplyShares)) / uint256(totalSupplyAssets);
    }

    /**
     * @dev Convert shares to assets using current rate
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        if (shares == 0) return 0;

        (uint128 totalSupplyAssets, uint128 totalSupplyShares,,,,) = MORPHO.market(marketId);

        if (totalSupplyAssets == 0 || totalSupplyShares == 0) {
            return shares; // 1:1 if no existing supply
        }

        // Calculate: shares * totalAssets / totalShares
        return (shares * uint256(totalSupplyAssets)) / uint256(totalSupplyShares);
    }

    /**
     * @dev IAdapter compliance - Mock implementations
     */
    function getPendingRewards() external pure override returns (uint256) {
        return 0; // Morpho auto-compounds, no external rewards
    }

    function harvest() external pure override returns (uint256) {
        return 0; // No harvest needed in Morpho
    }

    /**
     * @dev Get market ID
     */
    function getMarketId() external view returns (bytes32) {
        return Id.unwrap(marketId);
    }

    /**
     * @dev Get market parameters
     */
    function getMarketParams() external view returns (MarketParams memory) {
        return marketParams;
    }

    /**
     * @dev Accrue interest manually (optional)
     */
    function accrueInterest() external {
        MORPHO.accrueInterest(marketParams);
    }
}
