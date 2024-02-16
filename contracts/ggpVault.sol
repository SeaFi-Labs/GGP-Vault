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

contract GGPVault is
    Initializable,
    Ownable2StepUpgradeable,
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant APPROVED_NODE_OPERATOR = keccak256("APPROVED_NODE_OPERATOR");

    event MaxGGPAllowed(uint256 newMax);
    event TargetAPRUpdated(uint256 newTargetAPR);
    event WithdrawnForStaking(address indexed caller, uint256 assets);
    event DepositedFromStaking(address indexed caller, uint256 amount);
    event RewardsDistributed(uint256 amount);

    address public ggpStorage;
    uint256 public stakingTotalAssets;
    uint256 public maxGGPAllowed;
    uint256 public targetAPR;

    modifier onlyOwnerOrApprovedNodeOperator() {
        require(
            owner() == _msgSender() || hasRole(APPROVED_NODE_OPERATOR, _msgSender()),
            "Caller is not the owner or an approved node operator"
        );
        _;
    }

    function initialize(address _underlying, address _storageContract, address _initialOwner) external initializer {
        __ERC20_init("GGPVault", "ggGGP");
        __ERC4626_init(IERC20(_underlying));
        __UUPSUpgradeable_init();
        __Ownable2Step_init();
        __AccessControl_init();
        _transferOwnership(_initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        ggpStorage = _storageContract;
        maxGGPAllowed = 33000e18; // Starting asset cap
        targetAPR = 1836; // Starting target APR
    }

    function setMaxGGPAllowed(uint256 GGPDepositLimit) external onlyOwner {
        maxGGPAllowed = GGPDepositLimit;
        emit MaxGGPAllowed(maxGGPAllowed);
    }

    function setTargetAPR(uint256 target) external onlyOwner {
        targetAPR = target;
        emit TargetAPRUpdated(targetAPR);
    }

    function stakeAndIncreaseVaultSharePrice(uint256 amount, address nodeOp) external onlyOwnerOrApprovedNodeOperator {
        _stakeOnNode(amount, nodeOp); // this MUST be called before _distributeRewards
        _distributeRewards();
    }

    function stakeOnNode(uint256 amount, address nodeOp) external onlyOwnerOrApprovedNodeOperator {
        _stakeOnNode(amount, nodeOp);
    }

    function distributeRewards() external onlyOwnerOrApprovedNodeOperator {
        _distributeRewards();
    }

    function depositFromStaking(uint256 amount) external onlyOwnerOrApprovedNodeOperator {
        if (amount > stakingTotalAssets) {
            revert("Cant deposit more than the stakingTotalAssets");
        }
        stakingTotalAssets -= amount;
        emit DepositedFromStaking(_msgSender(), amount);
        IERC20(asset()).safeTransferFrom(_msgSender(), address(this), amount);
    }

    function totalAssets() public view override returns (uint256) {
        return stakingTotalAssets + getUnderlyingBalance();
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        uint256 total = totalAssets();
        return maxGGPAllowed > total ? maxGGPAllowed - total : 0;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 maxDepositAmount = maxDeposit(receiver);
        return (convertToShares(maxDepositAmount));
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 ownerBalance = balanceOf(owner);
        uint256 amountInVault = convertToShares(getUnderlyingBalance());
        if (amountInVault > ownerBalance) return ownerBalance;
        return amountInVault;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 maxRedeemAmount = maxRedeem(owner);
        return convertToAssets(maxRedeemAmount);
    }

    function getStakingContractAddress() public view returns (address) {
        bytes32 args = keccak256(abi.encodePacked("contract.address", "staking"));
        IStorageContractGGP storageContract = IStorageContractGGP(ggpStorage);
        return storageContract.getAddress(args);
    }

    function getRewardsBasedOnCurrentStakedAmount() public view returns (uint256) {
        return (targetAPR * stakingTotalAssets) / 10000 / 13;
    }

    function calculateAPYFromAPR() public view returns (uint256) {
        uint256 compoundingPeriods = 13; // Assuming compounding every 28 days
        uint256 aprFraction = targetAPR * 1e14; // Convert APR from basis points to a fraction
        uint256 oneScaled = 1e18; // Scale factor for precision
        uint256 compoundBase = oneScaled + aprFraction / compoundingPeriods;
        uint256 apyScaled = oneScaled;
        for (uint256 i = 0; i < compoundingPeriods; i++) {
            apyScaled = (apyScaled * compoundBase) / oneScaled;
        }
        return (apyScaled - oneScaled) / 1e14; // Convert back to basis points
    }

    function getUnderlyingBalance() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function _stakeOnNode(uint256 amount, address nodeOp) internal {
        _checkRole(APPROVED_NODE_OPERATOR, nodeOp);
        stakingTotalAssets += amount;

        IStakingContractGGP stakingContract = IStakingContractGGP(getStakingContractAddress());
        IERC20(asset()).approve(address(stakingContract), amount);
        stakingContract.stakeGGPOnBehalfOf(nodeOp, amount);
        emit WithdrawnForStaking(nodeOp, amount);
    }

    function _distributeRewards() internal {
        uint256 rewardAmount = getRewardsBasedOnCurrentStakedAmount();
        stakingTotalAssets += rewardAmount;
        emit RewardsDistributed(rewardAmount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
