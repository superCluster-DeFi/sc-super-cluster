// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {SuperCluster} from "../src/SuperCluster.sol";
import "forge-std/console2.sol";

contract SuperClusterDeploy is Script {
    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address sToken = vm.envAddress("STOKEN_ADDRESS");
        address wsToken = vm.envAddress("WSTOKEN_ADDRESS");
        address withdrawManager = vm.envAddress("WITHDRAW_MANAGER_ADDRESS");

        vm.startBroadcast(key);

        SuperCluster sc = new SuperCluster(usdc, sToken, wsToken, withdrawManager);

        console2.log("MockUSDC address:", usdc);
        console2.log("MockAave (not deployed here)");
        console2.log("SuperCluster deployed at:", address(sc));
        console2.log("sToken deployed at:", sToken);
        console2.log("wsToken deployed at:", wsToken);
        console2.log("WithdrawManager deployed at:", withdrawManager);

        vm.stopBroadcast();
    }
}
