// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

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
        mockStorage.setAddress(keccak256(abi.encodePacked("contract.address", "Staking")), address(mockStaking));

        address proxy = Upgrades.deployUUPSProxy(
            "GGPVault.sol",
            abi.encodeCall(GGPVault.initialize, (address(ggpToken), address(mockStorage), address(this)))
        );
        vault = GGPVault(proxy);

        vault.grantRole(vault.APPROVED_NODE_OPERATOR(), nodeOp1);
        ggpToken.approve(address(vault), type(uint256).max);

        ggpToken.transfer(nodeOp1, 100000e18);
        ggpToken.approve(address(vault), type(uint256).max);
        vm.prank(nodeOp1);
        ggpToken.approve(address(vault), type(uint256).max);
    }

    function testMaxMethods() public {
        console.logBytes32(keccak256(abi.encodePacked("contract.address", "Staking")));
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
        vault.stakeAndDistributeRewards(nodeOp1);
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
        vault.stakeAndDistributeRewards(nodeOp1);
        vault.stakeOnNode(0, nodeOp1);
        vault.distributeRewards();
        vault.depositFromStaking(0);

        // nodeOP can call all these methods
        vm.startPrank(nodeOp1);
        vault.stakeAndDistributeRewards(nodeOp1);
        vault.stakeOnNode(0, nodeOp1);
        vault.distributeRewards();
        vault.depositFromStaking(0);
        vm.stopPrank();
    }

    function getImplementationAddress(address proxy) public returns (address implementation) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        bytes32 data = vm.load(proxy, slot);
        implementation = address(uint160(uint256(data)));
    }

    function testInitalization() public {
        vm.expectRevert();
        vault.initialize(owner, owner, owner);
        address implementationAddress = getImplementationAddress(address(vault));
        GGPVault implementation = GGPVault(implementationAddress);
        vm.expectRevert();
        implementation.initialize(owner, owner, owner);
    }

    function testStakeAndDistributeRewards() public {
        assertEq(vault.totalAssets(), 0);
        vault.stakeAndDistributeRewards(nodeOp1);
        assertEq(vault.totalAssets(), 0, "rewards remain 0 when no staking asssets");
        vault.stakeAndDistributeRewards(nodeOp1);
        vault.stakeAndDistributeRewards(nodeOp1);
        vault.stakeAndDistributeRewards(nodeOp1);
        assertEq(vault.totalAssets(), 0, "calling multiple times doesnt change if stakingAssets is 0");

        uint256 originalDeposit = 100e18;
        vault.deposit(originalDeposit, address(this));
        vault.stakeAndDistributeRewards(nodeOp1);
        uint256 expectedStakeAmount = vault.previewRewardsAtStakedAmount(originalDeposit) + originalDeposit;
        assertEq(vault.stakingTotalAssets(), expectedStakeAmount, "confirm assets were staked + rewarded correctly");

        // calling again should cause it to increase rewards again
        vault.stakeAndDistributeRewards(nodeOp1);
        uint256 expectedStakeAmount2 = vault.previewRewardsAtStakedAmount(expectedStakeAmount) + expectedStakeAmount;
        assertEq(
            vault.stakingTotalAssets(),
            expectedStakeAmount2,
            "confirm assets were staked + rewarded correctly when calling 2x in a row (which shouldnt be done)"
        );

        // works even with GGP max supply
    }

    function testRewardsAtHighValues() public {
        uint256 halfMaxSupply = ggpToken.totalSupply() / 2;
        vault.setGGPCap(halfMaxSupply * 2);
        vault.deposit(halfMaxSupply, address(this));
        vault.stakeAndDistributeRewards(nodeOp1);
        uint256 expectedRewards = vault.previewRewardsAtStakedAmount(halfMaxSupply);
        uint256 expectedStakeAmount = expectedRewards + halfMaxSupply;
        assertEq(vault.stakingTotalAssets(), expectedStakeAmount, "confirm assets were staked + rewarded correctly");
    }

    function testPreviewRewardsChangesWithAPR() public {
        uint256 stakeAmount = 10000e18; // 10k GGP token
        uint256 maxDelta = 1e18;
        uint256 percent5 = 500; // 5% APR
        uint256 percent15 = 1500; // 15% APR
        uint256 percent50 = 5000; // 15% APR

        vault.setTargetAPR(percent5); // Set initial APR
        uint256 rewardsAt5 = vault.previewRewardsAtStakedAmount(stakeAmount);
        vault.setTargetAPR(percent15); // Change APR
        uint256 rewardsAt15 = vault.previewRewardsAtStakedAmount(stakeAmount);
        vault.setTargetAPR(percent50); // Change APR
        uint256 rewardsAt50 = vault.previewRewardsAtStakedAmount(stakeAmount);
        assertApproxEqAbs(rewardsAt5, 38e18, maxDelta);
        assertApproxEqAbs(rewardsAt15, 115e18, maxDelta);
        assertApproxEqAbs(rewardsAt50, 384e18, maxDelta);
    }
}
