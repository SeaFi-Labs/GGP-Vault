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
    uint256 public stakingTotalAssets;

    /// @notice The cap on the total assets the vault can manage.
    uint256 public assetCap;

    /// @notice Emitted when the asset cap is updated.
    event AssetCapUpdated(uint256 newCap);

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
        // __Ownable_init(_initialOwner); // TODO which??
        _transferOwnership(_initialOwner);

        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);

        ggpStorage = (_storageContract);
        stakingTotalAssets = 0;
        assetCap = 33000e18;
    }

    /// @notice Sets a new cap for the total assets the vault can manage.
    /// @param _newCap The new asset cap.
    function setAssetCap(uint256 _newCap) external onlyOwner {
        assetCap = _newCap;
        emit AssetCapUpdated(_newCap);
    }

    /// @notice Allows the staking of a specified amount of tokens on behalf of a node operator.
    /// @param amount The amount of tokens to stake.
    /// @param nodeOp The address of the node operator to stake on behalf of.
    function stakeOnValidator(uint256 amount, address nodeOp, uint256 rewardAmount) external onlyOwner {
        _checkRole(APPROVED_NODE_OPERATOR, nodeOp);
        stakingTotalAssets += amount;
        stakingTotalAssets += rewardAmount;
        emit DepositYield(amount);

        IStakingContractGGP stakingContract = IStakingContractGGP(getStakingContractAddress());
        IERC20(asset()).approve(address(stakingContract), amount);
        stakingContract.stakeGGPOnBehalfOf(nodeOp, amount);
        emit WithdrawnForStaking(nodeOp, amount);
    }

    /// @notice Allows depositing assets back into the vault from staking activities.
    /// @param amount The amount of assets to deposit.
    function depositFromStaking(uint256 amount) external onlyOwnerOrApprovedNodeOperator {
        stakingTotalAssets = amount >= stakingTotalAssets ? 0 : stakingTotalAssets - amount;
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
        if (false) {
            _receiver;
        }
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

    /// @notice Gets the balance of underlying assets held by the vault.
    /// @return The balance of underlying assets.
    function getUnderlyingBalance() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @dev Ensures only the owner can authorize upgrades to the contract implementation.
    /// @param newImplementation The address of the new contract implementation.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
