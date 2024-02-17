// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GGPVault} from "../contracts/GGPVault.sol";
import {MockTokenGGP} from "../test/mocks/MockTokenGGP.sol";
import {MockStaking} from "../test/mocks/MockStaking.sol";
import {MockStorage} from "../test/mocks/MockStorage.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployContracts {
    MockTokenGGP public ggpToken;
    MockStaking public mockStaking;
    MockStorage public mockStorage;
    GGPVault vault;

    function deploy() public {
        address devWallet1 = 0x232F3d6Ce02758aA4c592f115c995A34ADeAbE36;
        ggpToken = new MockTokenGGP(address(this));
        mockStaking = new MockStaking(ggpToken);
        mockStorage = new MockStorage();
        mockStorage.setAddress(keccak256(abi.encodePacked("contract.address", "staking")), address(mockStaking));
        address proxy = Upgrades.deployUUPSProxy(
            "GGPVault.sol", abi.encodeCall(GGPVault.initialize, (address(ggpToken), address(mockStorage), msg.sender))
        );
        vault = GGPVault(proxy);
        ggpToken.transfer(devWallet1, 10000e18);
        ggpToken.transfer(msg.sender, 10000e18);
    }

    function get1kGGP() public {
        ggpToken.transfer(msg.sender, 1000e18);
    }
}
