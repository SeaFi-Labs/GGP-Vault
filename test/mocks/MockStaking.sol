// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;
import {MockTokenGGP} from "./MockTokenGGP.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// GGP Governance and Utility Token
// Inflationary with rate determined by DAO

contract MockStaking {
    using SafeTransferLib for MockTokenGGP;
	using SafeTransferLib for address;
	event GGPStaked(address indexed from, uint256 amount);

    MockTokenGGP public ggp;
    constructor(MockTokenGGP _ggp) {
        ggp = _ggp;
    }
	function stakeGGPOnBehalfOf(address stakerAddr, uint256 amount) external {
		ggp.safeTransferFrom(msg.sender, address(this), amount);
        _stakeGGP(stakerAddr, amount);

    }

    function _stakeGGP(address stakerAddr, uint256 amount) internal  {
            emit GGPStaked(stakerAddr, amount);

        }


}

