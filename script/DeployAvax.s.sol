// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GGPVault} from "../contracts/GGPVault.sol";
import {MockTokenGGP} from "../test/mocks/MockTokenGGP.sol";
import {MockStaking} from "../test/mocks/MockStaking.sol";
import {MockStorage} from "../test/mocks/MockStorage.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "forge-std/Script.sol";

contract MyScript is Script {
    GGPVault vault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address GGPStorageMainnet = 0x1cEa17F9dE4De28FeB6A102988E12D4B90DfF1a9;
        address ggpTokenMainnet = 0x69260B9483F9871ca57f81A90D91E2F96c2Cd11d;
        vm.startBroadcast(deployerPrivateKey);

        Upgrades.deployUUPSProxy(
            "GGPVault.sol", abi.encodeCall(GGPVault.initialize, (ggpTokenMainnet, GGPStorageMainnet, msg.sender))
        );
        vm.stopBroadcast();
    }
}
