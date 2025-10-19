// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPilot {
    /**
     * @dev Invest funds according to pilot's strategy
     * @param amount Amount of IDRX to invest
     * @param adapters Array of adapter addresses to use
     * @param allocations Array of allocation percentages (must sum to 10000 = 100%)
     */
    function invest(uint256 amount, address[] calldata adapters, uint256[] calldata allocations) external;

    /**
     * @dev Divest funds from external protocols
     * @param amount Amount of IDRX to divest
     * @param adapters Array of adapter addresses to divest from
     * @param allocations Array of divestment percentages
     */
    function divest(uint256 amount, address[] calldata adapters, uint256[] calldata allocations) external;

    /**
     * @dev Harvest rewards from external protocols
     * @param adapters Array of adapter addresses to harvest from
     */
    function harvest(address[] calldata adapters) external;

    /**
     * @dev Get current strategy allocation
     * @return adapters Array of adapter addresses
     * @return allocations Array of current allocation percentages
     */
    function getStrategy() external view returns (address[] memory adapters, uint256[] memory allocations);

    /**
     * @dev Get total value managed by this pilot (including idle IDRX + adapter balances)
     * @return Total value in IDRX terms
     */
    function getTotalValue() external view returns (uint256);

    /**
     * @dev Get pilot's name
     */
    function name() external view returns (string memory);

    /**
     * @dev Get pilot's description
     */
    function description() external view returns (string memory);

    /**
     * @dev Set pilot's name (owner only)
     * @param _name New pilot name
     */
    function setPilot(string memory _name) external;

    /**
     * @dev Set pilot's description (owner only)
     * @param _description New pilot description
     */
    function setDescription(string memory _description) external;

    /**
     * @dev Set strategy allocation (owner only)
     * @param adapters Array of adapter addresses
     * @param allocations Array of allocation percentages (must sum to 10000)
     */
    function setPilotStrategy(address[] calldata adapters, uint256[] calldata allocations) external;

    /**
     * @dev Add adapter to active list (owner only)
     * @param adapter Adapter address to add
     */
    function addAdapter(address adapter) external;

    /**
     * @dev Remove adapter from active list (owner only)
     * @param adapter Adapter address to remove
     */
    function removeAdapter(address adapter) external;

    /**
     * @dev Emergency withdraw all IDRX tokens (owner only)
     */
    function emergencyWithdraw() external;

    /**
     * @dev Check if adapter is active
     * @param adapter Adapter address to check
     * @return True if adapter is active
     */
    function isActiveAdapter(address adapter) external view returns (bool);

    /**
     * @dev Receive funds from SuperCluster and auto-invest
     * @param amount Amount of IDRX received from SuperCluster
     */
    function receiveAndInvest(uint256 amount) external;

    /**
     * @dev Withdraw funds for user withdrawal from SuperCluster
     * @param amount Amount to withdraw for user
     */
    function withdrawForUser(uint256 amount) external;

    function withdrawToManager(address withdrawManager, uint256 amount) external;
}
