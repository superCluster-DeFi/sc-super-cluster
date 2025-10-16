// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {BaseToken} from "../src/tokens/BaseToken.sol";
import {SToken} from "../src/tokens/SToken.sol";
import {WsToken} from "../src/tokens/WsToken.sol";
import {Withdraw} from "../src/tokens/WithDraw.sol";

contract SuperClusterScript is Script {
    function run() external {
        // Load deployer private key from environment variable
        uint256 SuperClusterPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(SuperClusterPrivateKey);

        console.log("=== Super Cluster Smart Contracts ===");

        // 1. Deploy BaseToken
        BaseToken base = new BaseToken("Base Token", "BASE", 18);
        console.log("BaseToken deployed at:", address(base));

        // 2. Deploy SToken (rebasing)
        SToken sToken = new SToken("Staked Token", "sBASE", address(base), address(base));
        console.log("SToken deployed at:", address(sToken));

        // 3. Deploy WsToken (wrapped)
        WsToken wsToken = new WsToken(address(sToken));
        console.log("WsToken deployed at:", address(wsToken));

        // 4. Deploy Withdraw Manager (with 1-day delay)
        Withdraw withdraw = new Withdraw(
            address(sToken),
            address(base),
            address(0), // placeholder untuk SuperCluster
            1 days
        );
        console.log("Withdraw contract deployed at:", address(withdraw));

        console.log("Deployment complete!");
        console.log("BaseToken :", address(base));
        console.log("SToken    :", address(sToken));
        console.log("WsToken   :", address(wsToken));
        console.log("Withdraw  :", address(withdraw));

        vm.stopBroadcast();
    }
}
