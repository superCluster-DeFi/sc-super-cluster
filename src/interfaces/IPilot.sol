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
     * @dev Get total value managed by this pilot
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
}
