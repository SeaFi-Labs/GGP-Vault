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
        ggpToken = new MockTokenGGP(owner);
        mockStaking = new MockStaking(ggpToken);
        mockStorage = new MockStorage();
        mockStorage.setAddress(keccak256(abi.encodePacked("contract.address", "staking")), address(mockStaking));

        vault = new GGPVault();
        address GGPVaultMultisig = address(0x69);
        vault.initialize(address(ggpToken), address(mockStorage), GGPVaultMultisig);
    }

    function testWalkThroughEntireScenario() public {
        // Setup roles and addresses
        address nodeOp1 = address(0x999);
        address nodeOp2 = address(0x888);
        address randomUser1 = address(0x777);
        address randomUser2 = address(0x666);

        // Transfer tokens to users
        ggpToken.transfer(randomUser1, 10000e18);
        ggpToken.transfer(randomUser2, 10000e18);

        // Test re-initialization should revert
        vm.expectRevert();
        vault.initialize(address(ggpToken), address(mockStorage), address(0x69));

        // Test roles assignment should revert for unauthorized users
        bytes32 nodeOpRole = vault.APPROVED_NODE_OPERATOR();
        bytes32 defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();

        vm.expectRevert();
        vault.grantRole(nodeOpRole, address(0x69));

        vm.expectRevert();
        vault.grantRole(defaultAdminRole, address(0x69));

        // Check ownership and roles
        assertEq(vault.owner(), address(0x69), "Vault owner should be multisig address");
        assertEq(vault.hasRole(defaultAdminRole, address(0x69)), true, "Multisig should have default admin role");

        // Grant roles using multisig
        vm.startPrank(address(0x69));
        vault.grantRole(nodeOpRole, nodeOp1);
        vault.grantRole(nodeOpRole, nodeOp2);
        vm.stopPrank();

        // Deposit from randomUser1
        vm.startPrank(randomUser1);
        uint256 randomUser1InitialDeposit = 10e18;
        ggpToken.approve(address(vault), randomUser1InitialDeposit);
        vault.deposit(randomUser1InitialDeposit, randomUser1);
        assertEq(
            vault.balanceOf(randomUser1),
            randomUser1InitialDeposit,
            "User1's vault balance should match the initial deposit"
        );
        assertEq(vault.totalAssets(), randomUser1InitialDeposit, "Total vault assets should match User1's deposit");
        vm.stopPrank();

        // Deposit from randomUser2
        vm.startPrank(randomUser2);
        uint256 randomUser2InitialDeposit = 10000e18;
        ggpToken.approve(address(vault), randomUser2InitialDeposit);
        vault.deposit(randomUser2InitialDeposit, randomUser2);
        uint256 totalDeposits = randomUser1InitialDeposit + randomUser2InitialDeposit;
        assertEq(vault.totalAssets(), totalDeposits, "Total vault assets should match sum of User1 and User2 deposits");
        vm.stopPrank();

        // Withdraw from randomUser2
        vm.startPrank(randomUser2);
        uint256 randomUser2Withdrawal = 100e18;
        vault.withdraw(randomUser2Withdrawal, randomUser2, randomUser2);
        uint256 totalDepositsAfterWithdraw = totalDeposits - randomUser2Withdrawal;
        assertEq(
            vault.balanceOf(randomUser2),
            randomUser2InitialDeposit - randomUser2Withdrawal,
            "User2's vault balance should be reduced by the withdrawal amount"
        );
        assertEq(
            vault.totalAssets(),
            totalDepositsAfterWithdraw,
            "Total vault assets should be reduced by User2's withdrawal"
        );
        vm.stopPrank();

        // Stake and distribute rewards
        vm.startPrank(address(0x69));
        uint256 amountToStake = vault.totalAssets();
        uint256 stakingRewardsAt20PercentApy = vault.previewRewardsAtStakedAmount(amountToStake);
        vault.stakeAndDistributeRewards(amountToStake, nodeOp1);
        assertEq(
            vault.totalAssets(),
            amountToStake + stakingRewardsAt20PercentApy,
            "Total assets should include staked amount plus rewards"
        );
        vm.stopPrank();

        // Check max redeem and withdraw for randomUser2
        vm.startPrank(nodeOp1);
        uint256 maxRedeemUser2 = vault.maxRedeem(randomUser2);
        uint256 maxWithdrawUser2 = vault.maxWithdraw(randomUser2);
        assertApproxEqAbs(
            vault.previewWithdraw(maxWithdrawUser2),
            maxRedeemUser2,
            10,
            "Preview withdraw should approximately equal max redeem"
        );
        assertApproxEqAbs(
            vault.previewRedeem(maxRedeemUser2),
            maxWithdrawUser2,
            10,
            "Preview redeem should approximately equal max withdraw"
        );
        vm.stopPrank();
    }
}
