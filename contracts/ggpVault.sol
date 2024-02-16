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
/// @notice A vault for staking tokens with upgradeable functionality, compliant with the ERC4626 standard for tokenized vaults.
/// @dev Integrates functionalities from OpenZeppelin's UUPS, ERC4626, ERC20, Ownable2Step, and AccessControl upgradeable contracts.
contract GGPVault is
    Initializable,
    ERC20Upgradeable,
    ERC4626Upgradeable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice The role identifier for nodes approved to participate in staking operations.
    bytes32 public constant APPROVED_NODE_OPERATOR = keccak256("APPROVED_NODE_OPERATOR");

    /// @notice The address of the storage contract for GGP specific data.
    address public ggpStorage;

    /// @notice The total assets currently staked through the vault.
    uint256 public stakingTotalAssets;

    /// @notice The cap on the total assets the vault can manage.
    uint256 public assetCap;

    /// @notice The target annual percentage rate (APR) for staking, expressed in basis points.
    uint256 public targetAPR;

    /// @dev Emitted when the asset cap is updated.
    event AssetCapUpdated(uint256 newCap);

    /// @dev Emitted when the target APR is updated.
    event TargetAPRUpdated(uint256 newTargetAPR);

    /// @dev Emitted when assets are withdrawn for staking on behalf of a node operator.
    event WithdrawnForStaking(address indexed caller, uint256 assets);

    /// @dev Emitted when assets are deposited back into the vault from staking.
    event DepositedFromStaking(address indexed caller, uint256 amount);

    /// @dev Emitted when yield is deposited into the vault, increasing the vault share price.
    event DepositYield(uint256 amount);

    /// @dev Modifier to restrict access to the owner or an approved node operator.
    modifier onlyOwnerOrApprovedNodeOperator() {
        require(owner() == _msgSender() || hasRole(APPROVED_NODE_OPERATOR, _msgSender()), "Unauthorized");
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
        __AccessControl_init();
        _transferOwnership(_initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        ggpStorage = _storageContract;
        stakingTotalAssets = 0;
        assetCap = 33000e18; // Default cap
        targetAPR = 2000; // 20% APR in basis points
    }

    /// @notice Sets a new cap for the total assets the vault can manage.
    /// @param _assetCap The new asset cap.
    function setAssetCap(uint256 _assetCap) external onlyOwner {
        assetCap = _assetCap;
        emit AssetCapUpdated(assetCap);
    }

    /// @notice Sets a new target APR for the vault.
    /// @param _targetAPR The new target APR in basis points.
    function setTargetAPR(uint256 _targetAPR) external onlyOwner {
        targetAPR = _targetAPR;
        emit TargetAPRUpdated(targetAPR);
    }

    /// @notice Stakes a specified amount of tokens on behalf of a node operator.
    /// @param amount The amount of tokens to stake.
    /// @param nodeOp The address of the node operator to stake on behalf of.
    /// @param distributeRewards If true, distributes rewards by increasing the vault share price.
    function stakeOnValidator(uint256 amount, address nodeOp, bool distributeRewards)
        external
        onlyOwnerOrApprovedNodeOperator
    {
        _checkRole(APPROVED_NODE_OPERATOR, nodeOp);
        stakingTotalAssets += amount;
        if (distributeRewards) {
            _increaseVaultSharePrice();
        }
        IStakingContractGGP stakingContract = IStakingContractGGP(getStakingContractAddress());
        IERC20(asset()).approve(address(stakingContract), amount);
        stakingContract.stakeGGPOnBehalfOf(nodeOp, amount);
        emit WithdrawnForStaking(nodeOp, amount);
    }

    /// @notice Deposits assets back into the vault from staking activities.
    /// @param amount The amount of assets to deposit.
    function depositFromStaking(uint256 amount) external onlyOwnerOrApprovedNodeOperator {
        require(amount <= stakingTotalAssets, "Exceeds staked");
        stakingTotalAssets -= amount;
        emit DepositedFromStaking(_msgSender(), amount);
        IERC20(asset()).safeTransferFrom(_msgSender(), address(this), amount);
    }

    /// @notice Retrieves the address of the staking contract from the storage contract.
    /// @return The address of the staking contract.
    function getStakingContractAddress() public view returns (address) {
        return IStorageContractGGP(ggpStorage).getAddress(keccak256(abi.encodePacked("contract.address", "staking")));
    }

    /// @notice Calculates the total assets managed by the vault, including staked and unstaked assets.
    /// @return The total assets under management.
    function totalAssets() public view override returns (uint256) {
        return stakingTotalAssets + IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Determines the maximum amount that can be deposited for a given receiver, considering the asset cap.
    /// @param _receiver The address of the potential receiver of the deposit.
    /// @return The maximum amount that can be deposited.
    function maxDeposit(address _receiver) public view override returns (uint256) {
        uint256 total = totalAssets();
        return assetCap > total ? assetCap - total : 0;
    }

    /// @dev Increases the vault share price by depositing yield.
    function _increaseVaultSharePrice() internal {
        uint256 rewardAmount = getExpectedRewardCycleYield();
        stakingTotalAssets += rewardAmount;
        emit DepositYield(rewardAmount);
    }

    /// @notice Calculates the expected yield for a reward cycle.
    /// @return The expected monthly yield.
    function getExpectedRewardCycleYield() public view returns (uint256) {
        uint256 total = totalAssets();
        return (targetAPR * total) / 10000 / 13;
    }

    /// @notice Calculates the annual percentage yield (APY) from the target APR.
    /// @dev Compounds monthly.
    /// @return The APY in basis points.
    function calculateAPYFromAPR() public view returns (uint256) {
        uint256 compoundingPeriods = 365 / 28; // Compounding monthly
        uint256 aprFraction = targetAPR * 1e14;
        uint256 oneScaled = 1e18;
        uint256 compoundBase = oneScaled + aprFraction / compoundingPeriods;
        uint256 apyScaled = oneScaled;

        for (uint256 i = 0; i < compoundingPeriods; i++) {
            apyScaled = (apyScaled * compoundBase) / oneScaled;
        }

        return (apyScaled - oneScaled) / 1e14;
    }

    /// @dev Ensures only the owner can authorize upgrades to the contract implementation.
    /// @param newImplementation The address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
