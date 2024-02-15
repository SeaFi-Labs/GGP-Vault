// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

// GGP Governance and Utility Token
// Inflationary with rate determined by DAO

contract MockTokenGGP is ERC20 {
	uint256 private constant INITIAL_SUPPLY = 18_000_000 ether;
	uint256 public constant MAX_SUPPLY = 22_500_000 ether;
	constructor(address mintToAddress) ERC20("GoGoPool Protocol", "GGP", 18)  {
		_mint(mintToAddress, INITIAL_SUPPLY);
	}
}
