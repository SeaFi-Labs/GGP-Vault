// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/GGPInterfaces.sol";

/// @title GGPVault
/// @notice A vault contract for staking tokens with upgradeable functionality through UUPS and ERC4626 standard compliance for tokenized vaults.
/// @dev This contract integrates functionalities from OpenZeppelin's UUPS, ERC4626, ERC20, Ownable2Step, and AccessControl upgradeable contracts.
contract GGPVault is
    Initializable,
    Ownable2StepUpgradeable,
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Role identifier for nodes approved to participate in the staking operations.
    bytes32 public constant APPROVED_NODE_OPERATOR = keccak256("APPROVED_NODE_OPERATOR");

    /// @notice Reference to the storage contract for GGP specific data.
    address public ggpStorage;

    /// @notice Total assets currently staked through the vault.
    uint256 public stakingTotalAssets = 0;

    /// @notice The cap on the total assets the vault can manage.
    uint256 public assetCap = 33000e18;

    // 20% APY expressed in basis points for clarity
    uint256 public targetAPR = 1836; // 20% APY

    /// @notice Emitted when the asset cap is updated.
    event AssetCapUpdated(uint256 newCap);

    event TargetAPRUpdated(uint256 newTargetAPY);

    /// @notice Emitted when assets are withdrawn for staking on behalf of a node operator.
    event WithdrawnForStaking(address indexed caller, uint256 assets);

    /// @notice Emitted when assets are deposited back from staking.
    event DepositedFromStaking(address indexed caller, uint256 amount);

    event DepositYield(uint256 amount);
    // Modifier to restrict access to the owner or an approved node operator

    modifier onlyOwnerOrApprovedNodeOperator() {
        require(
            hasRole(APPROVED_NODE_OPERATOR, _msgSender()) || owner() == _msgSender(),
            "Caller is not the owner or an approved node operator"
        );
        _;
    }

    /// @notice Initializes the contract with necessary setups for roles, ERC20, ERC4626, and storage.
    /// @param _underlying The address of the underlying asset for the ERC4626 vault.
    /// @param _storageContract The address of the GGP specific storage contract.
    /// @param _initialOwner The initial owner of the contract with admin rights.
    function initialize(address _underlying, address _storageContract, address _initialOwner) external initializer {
        __ERC20_init("ggpVault", "ggGGP");
        __ERC4626_init(IERC20(_underlying));
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        _transferOwnership(_initialOwner);
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);

        ggpStorage = (_storageContract);
    }

    /// @notice Sets a new cap for the total assets the vault can manage.
    /// @param _assetCap The new asset cap.
    function setAssetCap(uint256 _assetCap) external onlyOwner {
        assetCap = _assetCap;
        emit AssetCapUpdated(assetCap);
    }

    function setTargetAPR(uint256 _targetAPR) external onlyOwner {
        targetAPR = _targetAPR;
        emit AssetCapUpdated(targetAPR);
    }

    /// @notice Allows the staking of a specified amount of tokens on behalf of a node operator.
    /// @param amount The amount of tokens to stake.
    /// @param nodeOp The address of the node operator to stake on behalf of.
    function stakeOnValidator(uint256 amount, address nodeOp, bool distributeRewards) external onlyOwner {
        _checkRole(APPROVED_NODE_OPERATOR, nodeOp);
        stakingTotalAssets += amount;
        if (distributeRewards) {
            // utility to stake + increase share price in the same transaction
            _increaseVaultSharePrice();
        }

        IStakingContractGGP stakingContract = IStakingContractGGP(getStakingContractAddress());
        IERC20(asset()).approve(address(stakingContract), amount);
        stakingContract.stakeGGPOnBehalfOf(nodeOp, amount);
        emit WithdrawnForStaking(nodeOp, amount);
    }

    function increaseVaultSharePrice() external onlyOwner {
        _increaseVaultSharePrice();
    }

    function _increaseVaultSharePrice() internal {
        uint256 rewardAmount = getExpectedRewardCycleYield();
        stakingTotalAssets += rewardAmount;
        emit DepositYield(rewardAmount);
    }

    /// @notice Allows depositing assets back into the vault from staking activities.
    /// @param amount The amount of assets to deposit.
    function depositFromStaking(uint256 amount) external onlyOwnerOrApprovedNodeOperator {
        if (amount > stakingTotalAssets) {
            revert("Can't deposit more than the stakingTotalAssets");
        }
        stakingTotalAssets -= amount;
        emit DepositedFromStaking(msg.sender, amount);
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Retrieves the address of the staking contract from the storage contract.
    /// @return The address of the staking contract as IStakingContractGGP.
    function getStakingContractAddress() public view returns (address) {
        bytes32 args = keccak256(abi.encodePacked("contract.address", "staking"));
        IStorageContractGGP storageContract = IStorageContractGGP(ggpStorage);
        return storageContract.getAddress(args);
    }

    /// @notice Calculates the total assets managed by the vault including staked and unstaked assets.
    /// @return The total assets under management.
    function totalAssets() public view override returns (uint256) {
        return stakingTotalAssets + getUnderlyingBalance();
    }

    /// @notice Determines the maximum amount that can be deposited for a given receiver, considering the asset cap.
    // / @param _receiver The address of the potential receiver of the deposit.
    /// @return The maximum amount that can be deposited.
    function maxDeposit(address _receiver) public view override returns (uint256) {
        uint256 total = totalAssets();
        return assetCap > total ? assetCap - total : 0;
    }

    function maxMint(address _receiver) public view override returns (uint256) {
        uint256 total = totalAssets();
        if (assetCap > total) return convertToShares(assetCap - total);
        return 0;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 ownerBalance = balanceOf(owner);
        uint256 amountInVault = convertToShares(getUnderlyingBalance());
        if (amountInVault > ownerBalance) return ownerBalance;
        return amountInVault;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 ownerBalance = convertToAssets(balanceOf(owner));
        uint256 amountInVault = getUnderlyingBalance();
        if (amountInVault > ownerBalance) return ownerBalance;
        return amountInVault;
    }

    function getExpectedRewardCycleYield() public view returns (uint256) {
        uint256 total = totalAssets();
        // Calculate the expected rewardCycle yield: (targetAPR / 100) * total assets / 13
        // Since targetAPR is in basis points, divide by 10000 to convert it to a percentage
        uint256 expectedMonthlyYield = (targetAPR * total) / 10000 / 13;
        return expectedMonthlyYield;
    }

    /// @notice Gets the balance of underlying assets held by the vault.
    /// @return The balance of underlying assets.
    function getUnderlyingBalance() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function calculateAPYFromAPR() public view returns (uint256) {
        uint256 daysInYear = 365;
        uint256 compoundingPeriods = daysInYear / 28; // Compounding every 28 days

        // Convert APR from basis points to a fraction scaled by 1e18 for precision
        uint256 aprFraction = targetAPR * 1e14; // APR as a fraction of 1, scaled up

        // Compound interest formula: (1 + apr/n)^n - 1
        // Using a loop to simulate compounding effect
        uint256 oneScaled = 1e18; // Scale factor for precision
        uint256 compoundBase = oneScaled + aprFraction / compoundingPeriods; // Base of compounding per period
        uint256 apyScaled = oneScaled; // Start with 1.0 scaled

        for (uint256 i = 0; i < compoundingPeriods; i++) {
            apyScaled = (apyScaled * compoundBase) / oneScaled;
        }

        // Convert back to basis points from scaled fraction
        uint256 apyBasisPoints = (apyScaled - oneScaled) / 1e14; // Subtract 1 (scaled) and convert to basis points

        return apyBasisPoints;
    }

    /// @dev Ensures only the owner can authorize upgrades to the contract implementation.
    /// @param newImplementation The address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
