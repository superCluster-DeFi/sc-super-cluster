// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MockOracle} from "../src/mocks/MockOracle.sol";
import {MockIrm} from "../src/mocks/MockIrm.sol";

contract DeployOracleAndIRM is Script {
    function run() external {
        uint256 superClusterPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(superClusterPrivateKey);

        console.log("=== Starting Oracle & IRM Deployment ===");
        MockOracle mockOracle = new MockOracle();
        console.log("Mock Oracle deployed at:", address(mockOracle));
        MockIrm mockIrm = new MockIrm();
        console.log("Mock IRM deployed at:", address(mockIrm));

        vm.stopBroadcast();
    }
}
