// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GGPVault} from "../contracts/GGPVault.sol";
import {MockTokenGGP} from "../test/mocks/MockTokenGGP.sol";
import {MockStaking} from "../test/mocks/MockStaking.sol";
import {MockStorage} from "../test/mocks/MockStorage.sol";

contract DeployContracts {
    MockTokenGGP public ggpToken;
    MockStaking public mockStaking;
    MockStorage public mockStorage;
    GGPVault vault;

    function deploy() public {
        ggpToken = new MockTokenGGP(msg.sender);
        mockStaking = new MockStaking(ggpToken);
        mockStorage = new MockStorage();
        mockStorage.setAddress(keccak256(abi.encodePacked("contract.address", "staking")), address(mockStaking));

        vault = new GGPVault(); // Deploy the GGP Vault
        vault.initialize(address(ggpToken), address(mockStorage), msg.sender); // initalize it and transfer ownership to our multis
    }
}
