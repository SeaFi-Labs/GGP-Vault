// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {GGPVault} from "../contracts/GGPVault.sol";
import {MockTokenGGP} from "./mocks/MockTokenGGP.sol";
import {MockStaking} from "./mocks/MockStaking.sol";
import {MockStorage} from "./mocks/MockStorage.sol";

contract GGPVaultTest is Test {
    GGPVault vault;
    MockTokenGGP ggpToken;
    MockStaking mockStaking;
    MockStorage mockStorage;
    address owner;
    address nodeOp1 = address(0x9);

    event GGPCapUpdated(uint256 newCap);
    event DepositedFromStaking(address indexed caller, uint256 amount);

    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        owner = address(this);
        ggpToken = new MockTokenGGP(address(this));
        mockStaking = new MockStaking(ggpToken);
        mockStorage = new MockStorage();
        mockStorage.setAddress(keccak256(abi.encodePacked("contract.address", "staking")), address(mockStaking));

        vault = new GGPVault();
        vault.initialize(address(ggpToken), address(mockStorage), address(this));
        vault.grantRole(vault.APPROVED_NODE_OPERATOR(), nodeOp1);
        ggpToken.approve(address(vault), type(uint256).max);

        ggpToken.transfer(nodeOp1, 100000e18);
        ggpToken.approve(address(vault), type(uint256).max);
        vm.prank(nodeOp1);
        ggpToken.approve(address(vault), type(uint256).max);
    }

    function testMaxMethods() public {
        uint256 maxDelta = 1e8;

        uint256 GGPCap = vault.GGPCap();
        assertEq(vault.maxDeposit(address(this)), GGPCap, "a");
        assertEq(vault.maxMint(address(this)), GGPCap, "a");
        assertEq(vault.maxWithdraw(address(this)), 0, "a");
        assertEq(vault.maxRedeem(address(this)), 0, "a");

        vault.setGGPCap(0);
        assertEq(vault.maxDeposit(address(this)), 0, "a");
        assertEq(vault.maxMint(address(this)), 0, "a");

        uint256 newCap = 100e18;
        vault.setGGPCap(newCap);
        assertEq(vault.maxDeposit(address(this)), newCap, "a");
        assertEq(vault.maxMint(address(this)), newCap, "a");

        uint256 depositedAssets = newCap / 2;
        vault.deposit(depositedAssets, address(this));
        assertEq(vault.maxDeposit(address(this)), depositedAssets, "a");
        assertEq(vault.maxMint(address(this)), depositedAssets, "a");
        assertEq(vault.maxWithdraw(address(this)), depositedAssets, "a");
        assertEq(vault.maxRedeem(address(this)), depositedAssets, "a");

        // double share value
        ggpToken.transfer(address(vault), depositedAssets);
        assertEq(vault.maxDeposit(address(this)), 0, "a");
        assertEq(vault.maxMint(address(this)), 0, "a");
        assertApproxEqAbs(vault.maxWithdraw(address(this)), depositedAssets * 2, maxDelta, "a");
        assertApproxEqAbs(vault.maxRedeem(address(this)), depositedAssets, maxDelta, "a");

        // update values correctly when GGP goes for staking
        vault.stakeOnNode(depositedAssets, nodeOp1);
        assertEq(vault.maxDeposit(address(this)), 0, "a");
        assertEq(vault.maxMint(address(this)), 0, "a");
        assertApproxEqAbs(vault.maxWithdraw(address(this)), depositedAssets, maxDelta, "a");
        assertApproxEqAbs(vault.maxRedeem(address(this)), depositedAssets / 2, maxDelta, "a");
    }

    function testOwnershipNonOwner() public {
        address randomUser = address(0x1337);
        bytes memory encodedCall = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, randomUser);
        vm.startPrank(randomUser);

        // Random person can't call stuff
        vm.expectRevert(encodedCall);
        vault.setGGPCap(0);
        vm.expectRevert(encodedCall);
        vault.setTargetAPR(0);
        vm.expectRevert("Caller is not the owner or an approved node operator");
        vault.stakeAndDistributeRewards(0, nodeOp1);
        vm.expectRevert("Caller is not the owner or an approved node operator");
        vault.stakeOnNode(0, nodeOp1);
        vm.expectRevert("Caller is not the owner or an approved node operator");
        vault.distributeRewards();
        vm.expectRevert("Caller is not the owner or an approved node operator");
        vault.depositFromStaking(0);

        vm.stopPrank();

        // Node Op can't call stuff
        bytes memory encodedCallNodeOp = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nodeOp1);

        vm.startPrank(nodeOp1);
        vm.expectRevert(encodedCallNodeOp);
        vault.setGGPCap(0);
        vm.expectRevert(encodedCallNodeOp);
        vault.setTargetAPR(0);
        vm.stopPrank();
    }

    function testOwnershipOwner() public {
        // owner can call all these methods
        assertEq(address(this), vault.owner());
        vault.setGGPCap(0);
        vault.setTargetAPR(0);
        vault.stakeAndDistributeRewards(0, nodeOp1);
        vault.stakeOnNode(0, nodeOp1);
        vault.distributeRewards();
        vault.depositFromStaking(0);

        // nodeOP can call all these methods
        vm.startPrank(nodeOp1);
        vault.stakeAndDistributeRewards(0, nodeOp1);
        vault.stakeOnNode(0, nodeOp1);
        vault.distributeRewards();
        vault.depositFromStaking(0);
        vm.stopPrank();
    }
}
