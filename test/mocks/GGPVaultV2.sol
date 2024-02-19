// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.20;

import {GGPVault} from "../../contracts/GGPVault.sol";

/// @custom:oz-upgrades-from GGPVault
contract GGPVaultV2 is GGPVault {
    function newMethod() public pure returns (string memory) {
        return "meow";
    }
}
