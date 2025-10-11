// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IAdapter {
    /**
     * @dev Deposit funds to the external protocol
     * @param amount Amount of IDRX to deposit
     * @return shares Shares received from the protocol
     */
    function deposit(uint256 amount) external returns (uint256 shares);

    /**
     * @dev Withdraw funds from the external protocol
     * @param shares Amount of shares to withdraw
     * @return amount Amount of IDRX received
     */
    function withdraw(uint256 shares) external returns (uint256 amount);

    /**
     * @dev Get current balance in the external protocol
     * @return balance Current balance in IDRX terms
     */
    function getBalance() external view returns (uint256 balance);

    /**
     * @dev Get pending rewards from the external protocol
     * @return rewards Pending rewards in IDRX terms
     */
    function getPendingRewards() external view returns (uint256 rewards);

    /**
     * @dev Harvest rewards from the external protocol
     * @return harvested Amount of rewards harvested in IDRX terms
     */
    function harvest() external returns (uint256 harvested);

    /**
     * @dev Get the external protocol name
     * @return protocolName Name of the external protocol
     */
    function getProtocolName() external view returns (string memory protocolName);

    /**
     * @dev Get the external protocol address
     * @return protocolAddress Address of the external protocol
     */
    function getProtocolAddress() external view returns (address protocolAddress);

    /**
     * @dev Check if the adapter is active
     * @return isActive True if adapter is active
     */
    function isActive() external view returns (bool isActive);

    /**
     * @dev Convert assets to shares
     * @param assets Amount of assets to convert
     * @return shares Amount of shares
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Get the pilot strategy name
     * @return strategy The pilot strategy name
     */
    function getPilotStrategy() external view returns (string memory strategy);
}
