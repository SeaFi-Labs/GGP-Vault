// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GGPVault} from "../contracts/GGPVault.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";

contract MyScript is Script {
    GGPVault vault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address ggpStorageMainnet = 0x1cEa17F9dE4De28FeB6A102988E12D4B90DfF1a9;
        address ggpTokenMainnet = 0x69260B9483F9871ca57f81A90D91E2F96c2Cd11d;
        // address originalNodeOp = 0x2Ff60357027861F25C7a6650564C2A606d23369d;
        address multisigGGPVault = 0x73F9d1761eDd28BFEd67c7d5BbfEDf85A3783309;
        vm.startBroadcast(deployerPrivateKey);

        Upgrades.deployUUPSProxy(
            "GGPVault.sol", abi.encodeCall(GGPVault.initialize, (ggpTokenMainnet, ggpStorageMainnet, multisigGGPVault))
        );
        // vault = GGPVault(proxy);

        // must be called from the safe
        // vault.grantRole(vault.APPROVED_NODE_OPERATOR(), originalNodeOp);

        vm.stopBroadcast();
    }
}
