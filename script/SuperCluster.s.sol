// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {MockUSDC} from "../src/mocks/tokens/MockUSDC.sol";
import {SuperCluster} from "../src/SuperCluster.sol";
import {MockMorpho} from "../src/mocks/MockMorpho.sol";
import {LendingPool} from "../src/mocks/MockAave.sol";
import {AaveAdapter} from "../src/adapter/AaveAdapter.sol";
import {MorphoAdapter} from "../src/adapter/MorphoAdapter.sol";
import {Pilot} from "../src/pilot/Pilot.sol";
import {MarketParams} from "../src/mocks/MockMorpho.sol";

contract SuperClusterScript is Script {
    function run() external {
        // Load deployer private key from environment variable
        uint256 SuperClusterPrivateKey = vm.envUint("PRIVATE_KEY");
        address mockOracle = address(0x1);
        uint256 lltv = 800000000000000000;

        // Start broadcasting transactions
        vm.startBroadcast(SuperClusterPrivateKey);

        console.log("=== Mock USDC Smart Contracts ===");
        MockUSDC base = new MockUSDC();
        console.log("BaseToken deployed at:", address(base));

        console.log("=== Super Cluster Smart Contracts ===");
        SuperCluster supercluster = new SuperCluster(address(base));
        console.log("SuperCluster deployed at:", address(supercluster));

        console.log("=== Mock Lending Protocol ===");

        console.log("=== Aave Smart Contracts ===");
        LendingPool mockAave = new LendingPool(address(base), address(base), mockOracle, lltv);
        console.log("MockAave LendingPool deployed at:", address(mockAave));

        console.log("=== ADAPTER ===");

        console.log("=== Aave Adapter Smart Contracts ===");
        AaveAdapter aaveAdapter = new AaveAdapter(address(base), address(mockAave), "Aave V3", "Conservative Lending");
        console.log("AaveAdapter deployed at:", address(aaveAdapter));

        console.log("=== Pilot ===");
        Pilot pilot = new Pilot(
            "Conservative DeFi Pilot",
            "Low-risk DeFi strategies focusing on lending protocols",
            address(base),
            address(supercluster)
        );
        console.log("Pilot deployed at:", address(pilot));

        address[] memory adapters = new address[](1);
        uint256[] memory allocations = new uint256[](1);

        adapters[0] = address(aaveAdapter);
        allocations[0] = 10000; // 100% Aave

        pilot.setPilotStrategy(adapters, allocations);

        supercluster.registerPilot(address(pilot), address(base));

        vm.stopBroadcast();
    }
}
