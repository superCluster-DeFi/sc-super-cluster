// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {MockUSDC} from "../src/mocks/tokens/MockUSDC.sol";
import {SuperCluster} from "../src/SuperCluster.sol";

contract SuperClusterScript is Script {
    function run() external {
        // Load deployer private key from environment variable
        uint256 SuperClusterPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(SuperClusterPrivateKey);

        console.log("=== Super Cluster Smart Contracts ===");

        // 1. Deploy BaseToken
        MockUSDC base = new MockUSDC();
        console.log("BaseToken deployed at:", address(base));

        SuperCluster supercluster = new SuperCluster(address(base));
        console.log("SuperCluster deployed at:", address(supercluster));

        vm.stopBroadcast();
    }
}
