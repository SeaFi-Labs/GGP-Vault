// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {GGPVault} from "../contracts/GGPVault.sol";
import {MockTokenGGP} from "./mocks/MockTokenGGP.sol";
import {MockStaking} from "./mocks/MockStaking.sol";
import {MockStorage} from "./mocks/MockStorage.sol";

contract GGPVaultTest2 is Test {
    GGPVault vault;
    MockTokenGGP ggpToken;
    MockStaking mockStaking;
    MockStorage mockStorage;
    address owner;

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
    }

    function testWalkThroughEntireScenerio() public {
        address nodeOp1 = address(0x999);
        address nodeOp2 = address(0x888);
        address randomUser1 = address(0x777);
        address randomUser2 = address(0x666);
        ggpToken.transfer(randomUser1, 10000e18);
        ggpToken.transfer(randomUser2, 10000e18);
        address GGPVaultMultisig = address(0x69);
        vault = new GGPVault();
        vault.initialize(address(ggpToken), address(mockStorage), GGPVaultMultisig);
        vm.expectRevert();
        vault.initialize(address(ggpToken), address(mockStorage), GGPVaultMultisig);
        bytes32 nodeOpRole = vault.APPROVED_NODE_OPERATOR();
        bytes32 defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();
        vm.expectRevert();
        vault.grantRole(nodeOpRole, GGPVaultMultisig);
        vm.expectRevert();
        vault.grantRole(defaultAdminRole, GGPVaultMultisig);
        vm.expectRevert();
        vault.transferOwnership(address(0x5));
        assertEq(vault.owner(), GGPVaultMultisig);
        assertEq(vault.hasRole(defaultAdminRole, GGPVaultMultisig), true);
        vm.startPrank(GGPVaultMultisig);
        vault.grantRole(nodeOpRole, nodeOp1);
        vault.grantRole(nodeOpRole, nodeOp2);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.getUnderlyingBalance(), 0);
        assertEq(vault.stakingTotalAssets(), 0);
        assertEq(vault.getStakingContractAddress(), address(mockStaking));
        assertEq(vault.ggpStorage(), address(mockStorage));
        assertEq(vault.GGPCap(), 33000e18);
        assertEq(vault.maxDeposit(GGPVaultMultisig), vault.GGPCap());
        vm.stopPrank();
        vm.startPrank(randomUser1);
        uint256 randomUser1InitialDeposit = 10e18;
        ggpToken.approve(address(vault), randomUser1InitialDeposit);
        vault.deposit(randomUser1InitialDeposit, randomUser1);
        assertEq(vault.balanceOf(randomUser1), randomUser1InitialDeposit);
        assertEq(vault.totalAssets(), randomUser1InitialDeposit);
        assertEq(vault.getUnderlyingBalance(), randomUser1InitialDeposit);
        assertEq(vault.stakingTotalAssets(), 0);
        assertEq(vault.maxDeposit(GGPVaultMultisig), vault.GGPCap() - randomUser1InitialDeposit);
        vm.stopPrank();
        vm.startPrank(randomUser2);
        uint256 randomUser2InitialDeposit = 10000e18;
        ggpToken.approve(address(vault), randomUser2InitialDeposit);
        vault.deposit(randomUser2InitialDeposit, randomUser2);
        assertEq(vault.balanceOf(randomUser2), randomUser2InitialDeposit);
        uint256 totalDeposits = randomUser1InitialDeposit + randomUser2InitialDeposit;
        assertEq(vault.totalAssets(), totalDeposits);
        assertEq(vault.getUnderlyingBalance(), totalDeposits);
        assertEq(vault.stakingTotalAssets(), 0);
        assertEq(vault.maxDeposit(GGPVaultMultisig), vault.GGPCap() - totalDeposits);
        uint256 randomUser2Withdrawal = 100e18;
        vault.withdraw(randomUser2Withdrawal, randomUser2, randomUser2);
        uint256 totalDepositsAfterWithdraw1 = totalDeposits - randomUser2Withdrawal;
        uint256 expectedUser2Deposits = totalDepositsAfterWithdraw1 - randomUser1InitialDeposit;
        assertEq(vault.balanceOf(randomUser2), expectedUser2Deposits);
        assertEq(vault.totalAssets(), totalDepositsAfterWithdraw1);
        assertEq(vault.getUnderlyingBalance(), totalDepositsAfterWithdraw1);
        assertEq(vault.stakingTotalAssets(), 0);
        assertEq(vault.maxDeposit(GGPVaultMultisig), vault.GGPCap() - totalDepositsAfterWithdraw1);
        vm.stopPrank();
        vm.startPrank(GGPVaultMultisig);
        uint256 amountToStake = vault.totalAssets();
        address nodeOp1_ = nodeOp1;
        uint256 stakingRewardsAt20PercentApy = vault.previewRewardsAtStakedAmount(amountToStake);
        vault.stakeAndDistributeRewards(amountToStake, nodeOp1_);
        assertEq(vault.totalAssets(), amountToStake + stakingRewardsAt20PercentApy);
        assertEq(vault.getUnderlyingBalance(), 0);
        assertEq(vault.stakingTotalAssets(), amountToStake + stakingRewardsAt20PercentApy);
        vm.stopPrank();
        vm.startPrank(nodeOp1_);
        address randomUser2_ = randomUser2;
        uint256 maxRedeemUser2 = vault.maxRedeem(randomUser2_);
        uint256 maxWithdrawUser2 = vault.maxWithdraw(randomUser2_);
        assertApproxEqAbs(vault.previewWithdraw(maxWithdrawUser2), vault.maxRedeem(randomUser2_), 10);
        assertApproxEqAbs(vault.previewRedeem(maxRedeemUser2), vault.maxWithdraw(randomUser2_), 10);
        assertEq(maxWithdrawUser2, vault.getUnderlyingBalance());
    }
}
