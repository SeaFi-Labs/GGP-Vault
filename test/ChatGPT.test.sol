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

    function testStakeOnNode() public {
        uint256 amount = 10e18; // 10 GGP for simplicity

        vault.deposit(amount, msg.sender);
        assertEq(vault.balanceOf(msg.sender), amount, "Depositor gets correct amount of shares");
        vault.stakeOnNode(amount, nodeOp1);

        assertEq(vault.stakingTotalAssets(), amount, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), amount, "The total assets should be equal to deposits");
    }

    function testTotalAssetsCalculation() public {
        uint256 assetsToDeposit = 1000e18; // Simulated staked amount
        assertEq(vault.stakingTotalAssets(), 0, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), 0, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), 0, "The total assets should be equal to deposits");

        vault.deposit(assetsToDeposit, msg.sender);
        assertEq(vault.stakingTotalAssets(), 0, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit, "The total assets should be equal to deposits");

        vault.stakeOnNode(assetsToDeposit / 2, nodeOp1);
        assertEq(vault.stakingTotalAssets(), assetsToDeposit / 2, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit / 2, "The total assets should be equal to deposits");

        vault.depositFromStaking(assetsToDeposit / 2);
        assertEq(vault.stakingTotalAssets(), 0, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit, "The total assets should be equal to deposits");

        uint256 rewards = vault.getRewardsBasedOnCurrentStakedAmount();
        vault.distributeRewards();
        assertEq(vault.stakingTotalAssets(), rewards, "The staking total assets should be updated");
        assertEq(vault.totalAssets(), assetsToDeposit + rewards, "The total assets should be equal to deposits");
        assertEq(vault.getUnderlyingBalance(), assetsToDeposit, "The total assets should be equal to deposits");
    }

    function testInitialization() public {
        assertEq(vault.ggpStorage(), address(mockStorage), "GGP Storage should be correctly set");
        assertEq(vault.stakingTotalAssets(), 0, "Staking total assets should initially be 0");
        assertEq(vault.GGPCap(), 33000e18, "Asset cap should be correctly set to 33000e18");

        // Verify the initial owner is correctly set
        assertEq(vault.owner(), owner, "The initial owner should be correctly set");

        // Check that the initial owner has the DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = vault.DEFAULT_ADMIN_ROLE();
        assertTrue(vault.hasRole(defaultAdminRole, owner), "The initial owner should have the DEFAULT_ADMIN_ROLE");

        // Optionally, verify the token and staking contract addresses
        assertEq(address(ggpToken), vault.asset(), "The underlying token address should be correctly set");
        assertEq(
            address(mockStaking),
            address(vault.getStakingContractAddress()),
            "The staking contract address should be correctly set"
        );
    }

    function testSetGGPCapSuccess() public {
        uint256 newGGPCap = 20000e18; // Define a new asset cap different from the initial one

        // Expect the GGPCapUpdated event to be emitted with the new asset cap value
        vm.expectEmit(true, true, true, true);
        emit GGPCapUpdated(newGGPCap);

        // Attempt to set the new asset cap as the owner
        vault.setGGPCap(newGGPCap);
        // Verify the asset cap was successfully updated
        assertEq(vault.GGPCap(), newGGPCap, "Asset cap should be updated to the new value");
    }

    function testSetGGPCapFailureNonOwner() public {
        uint256 newGGPCap = 20000e18; // Define a new asset cap
        address nonOwner = address(0x1); // Assume this address is not the owner

        // Set the next caller to be a non-owner
        vm.prank(nonOwner);

        // Attempt to set the new asset cap as a non-owner and expect it to revert
        // Adjust the revert message to match the actual error message in your contract
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonOwner));
        vault.setGGPCap(newGGPCap);
    }

    function testDepositFromStakingFailureUnauthorized() public {
        uint256 depositAmount = 100e18; // Example amount
        address unauthorized = address(0x2); // Example unauthorized address

        vm.startPrank(unauthorized);
        vm.expectRevert("Caller is not the owner or an approved node operator"); // Adjust based on your actual revert message
        vault.depositFromStaking(depositAmount);
        vm.stopPrank();
    }

    function testMaxDepositUnderNormalConditions() public {
        uint256 GGPCap = 33000e18; // Set the asset cap to 33,000 tokens for this test
        uint256 depositedAssets = 10000e18; // Simulate depositing 10,000 tokens
        vault.setGGPCap(GGPCap);
        vault.deposit(depositedAssets, address(this)); // Assume deposit function updates total assets correctly

        uint256 expectedMaxDeposit = GGPCap - depositedAssets;
        assertEq(
            vault.maxDeposit(address(this)),
            expectedMaxDeposit,
            "Max deposit should match the expected value under normal conditions"
        );
    }

    function testMaxDepositWhenVaultIsFull() public {
        uint256 GGPCap = 33000e18; // Asset cap is 33,000 tokens
        vault.setGGPCap(GGPCap);
        vault.deposit(GGPCap, address(this)); // Assume the vault is now full

        uint256 expectedMaxDeposit = 0;
        assertEq(vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should be 0 when the vault is full");
    }

    function testMaxDepositExceedsGGPCap() public {
        uint256 GGPCap = 33000e18; // Asset cap is 33,000 tokens
        uint256 depositedAssets = 32000e18; // Simulate depositing 32,000 tokens, close to the cap
        vault.setGGPCap(GGPCap);
        vault.deposit(depositedAssets, address(this)); // Assume deposit function updates total assets correctly

        uint256 expectedMaxDeposit = GGPCap - depositedAssets;
        assertEq(
            vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should not allow exceeding the asset cap"
        );
    }

    function testMaxDepositWithZeroGGPCap() public {
        uint256 GGPCap = 0; // Set the asset cap to 0
        vault.setGGPCap(GGPCap);

        uint256 expectedMaxDeposit = 0;
        assertEq(vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should be 0 with a zero asset cap");
    }

    function testMaxDepositWithNoAssetsInVault() public {
        uint256 GGPCap = 33000e18; // Set a non-zero asset cap
        vault.setGGPCap(GGPCap);

        uint256 expectedMaxDeposit = GGPCap; // With no assets in vault, max deposit should equal the asset cap
        assertEq(
            vault.maxDeposit(address(this)),
            expectedMaxDeposit,
            "Max deposit should equal the asset cap with no assets in vault"
        );
    }

    function testMaxDepositAfterWithdrawals() public {
        uint256 GGPCap = 33000e18;
        uint256 initialDeposit = 20000e18;
        uint256 withdrawalAmount = 5000e18; // Simulate a withdrawal reducing the total assets
        vault.setGGPCap(GGPCap);
        vault.deposit(initialDeposit, address(this)); // Assume deposit function updates total assets correctly
        vault.withdraw(withdrawalAmount, address(this), address(this)); // Assume withdrawal function updates total assets correctly

        uint256 expectedMaxDeposit = GGPCap - (initialDeposit - withdrawalAmount);
        assertEq(
            vault.maxDeposit(address(this)),
            expectedMaxDeposit,
            "Max deposit should be adjusted correctly after withdrawals"
        );

        uint256 oneMoreThanMaxDeposit = vault.maxDeposit(address(this)) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626ExceededMaxDeposit.selector, address(this), oneMoreThanMaxDeposit, expectedMaxDeposit
            )
        );

        vault.deposit(oneMoreThanMaxDeposit, address(this)); // Assume deposit function updates total assets correctly
    }

    function testMaxDepositWithChangingGGPCap() public {
        uint256 initialGGPCap = 33000e18;
        uint256 newGGPCap = 50000e18; // Increase the asset cap
        uint256 depositedAssets = 10000e18;
        vault.setGGPCap(initialGGPCap);
        vault.deposit(depositedAssets, address(this)); // Assume deposit function updates total assets correctly

        // Increase the asset cap
        vault.setGGPCap(newGGPCap);

        uint256 expectedMaxDeposit = newGGPCap - depositedAssets;
        assertEq(vault.maxDeposit(address(this)), expectedMaxDeposit, "Max deposit should reflect the new asset cap");
    }

    function testMaxMintScenariosWithExpectedValues() public {
        uint256 GGPCap = 33000e18; // Set the asset cap
        vault.setGGPCap(GGPCap);

        // Assuming the minting calculation is directly related to the asset cap and current total assets
        // For simplicity, let's assume 1 token deposited = 1 share minted (1:1 ratio)

        // Test with no assets in vault
        uint256 expectedMaxMintNoAssets = GGPCap; // Since no assets, maxMint should allow up to the asset cap
        uint256 maxMintNoAssets = vault.maxMint(address(this));
        assertEq(maxMintNoAssets, expectedMaxMintNoAssets, "Max mint should equal asset cap with no assets in vault");

        // Deposit assets and test under normal conditions
        uint256 initialDeposit = 10000e18;
        vault.deposit(initialDeposit, address(this));
        uint256 expectedMaxMintNormal = GGPCap - initialDeposit; // Adjusted for deposited assets
        uint256 maxMintNormal = vault.maxMint(address(this));
        assertEq(maxMintNormal, expectedMaxMintNormal, "Max mint should adjust based on deposited assets");

        // Withdraw assets and test maxMint adjustment
        uint256 withdrawalAmount = 5000e18;
        vault.withdraw(withdrawalAmount, address(this), address(this));
        uint256 expectedMaxMintAfterWithdrawal = expectedMaxMintNormal + withdrawalAmount; // Increase by the withdrawn amount
        uint256 maxMintAfterWithdrawal = vault.maxMint(address(this));
        assertEq(maxMintAfterWithdrawal, expectedMaxMintAfterWithdrawal, "Max mint should increase after withdrawals");

        // Deposit more assets to fill the vault to its cap
        uint256 additionalDepositToFill = GGPCap - initialDeposit + withdrawalAmount;
        vault.deposit(additionalDepositToFill, address(this));
        uint256 maxMintFullVault = vault.maxMint(address(this));
        assertEq(maxMintFullVault, 0, "Max mint should be 0 when vault is full");

        // Withdraw to below the cap and check maxMint adjustment
        vault.withdraw(withdrawalAmount, address(this), address(this));
        uint256 expectedMaxMintAfterSecondWithdrawal = withdrawalAmount; // Should allow minting up to the amount withdrawn to be below cap
        uint256 maxMintAfterSecondWithdrawal = vault.maxMint(address(this));
        assertEq(
            maxMintAfterSecondWithdrawal,
            expectedMaxMintAfterSecondWithdrawal,
            "Max mint should adjust correctly after second withdrawal"
        );
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
}
