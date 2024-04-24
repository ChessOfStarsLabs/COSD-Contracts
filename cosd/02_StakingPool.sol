// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingPoolV2 is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public token;               // 质押的 ERC20 代币
    IERC20 public rewardToken;         // 奖励代币，本例中是 USDT
    uint256 public rewardRateInit;     // 年华收益率
    uint256 public lockupPeriod;       // 锁定期，初步设为 30 天
    uint256 public stakingStartTime;   // 项目 staking 开始时间
    uint256 public stakingCap;         // 质押总量的上限
    uint256 public minStakeAmount;     // 最小质押数量


    mapping(address => uint256) public stakingBalance;  // 各个用户质押的代币数量
    mapping(address => uint256) public stakingTime;     // 各个用户质押的时间
    mapping(address => uint256) public stakingReward;   // 各个用户已经获得的奖励金额

    uint256 public totalStake;  // 池子中的总质押量
    uint256 public totalReward; // 池子中的总奖励

    uint256 public dayTime; // 每天一共有 86400 秒

    event Stake(address indexed user, uint256 amount);
    event UnStake(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _token, address _rewardToken, uint256 _rewardRateInit, uint256 _lockupPeriod,uint256 _stakingCap,uint256 _minStakeAmount) initializer public {
        token = IERC20(_token);
        rewardToken = IERC20(_rewardToken);
        rewardRateInit = _rewardRateInit;
        lockupPeriod = _lockupPeriod;
        stakingStartTime = block.timestamp;
        stakingCap = _stakingCap;
        minStakeAmount = _minStakeAmount;
        dayTime = 86400;
        // 初始化 ReentrancyGuard
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    // 质押代币
    function stake(uint256 _amount) external nonReentrant whenNotPaused{
        require(block.timestamp < stakingStartTime + lockupPeriod, "The current staking event has ended");
        require(_amount >= minStakeAmount, "Amount is below the minimum stake requirement");  // 新增：检查质押数量是否低于最小值
        require(totalStake + _amount <= stakingCap, "Staking cap exceeded");
        token.safeTransferFrom(msg.sender, address(this), _amount);
        stakingBalance[msg.sender] = stakingBalance[msg.sender] + _amount;
        stakingTime[msg.sender] = block.timestamp;
        uint256 reward = getRewardForUser(msg.sender,_amount);
        stakingReward[msg.sender] = stakingReward[msg.sender] + reward;
        totalStake = totalStake + _amount;
        totalReward = totalReward + reward;
        emit Stake(msg.sender, _amount);
    }

    // 撤回代币，仅在锁定期后允许
    function unStake(uint256 _amount) external nonReentrant whenNotPaused{
        require(block.timestamp >= (stakingStartTime + lockupPeriod), "Locked");
        require(stakingBalance[msg.sender] >= _amount, "Insufficient balance");
        token.safeTransfer(msg.sender, _amount);
        stakingBalance[msg.sender] = stakingBalance[msg.sender] - _amount;
        totalStake = totalStake - _amount;
        emit UnStake(msg.sender, _amount);
    }

    // 提取奖励
    function claimReward() external nonReentrant whenNotPaused{
        require(block.timestamp >= (stakingStartTime + lockupPeriod), "Locked");
        uint256 reward = stakingReward[msg.sender];
        rewardToken.safeTransfer(msg.sender, reward);
        stakingReward[msg.sender]=0;
        totalReward = totalReward - reward;
        emit ClaimReward(msg.sender, reward);
    }

    // 获取用户的累计奖励，不会实际转账
    function getRewardForUser(address account,uint256 _amount) internal view returns (uint256) {
        uint256 stakingDaysRemaining = (lockupPeriod + stakingStartTime - stakingTime[account]) / dayTime + 1; // 计算用户已经质押的天数，不足一天按1天计算
        uint256 reward = _amount * 27398 / 1e9 * rewardRateInit * stakingDaysRemaining;
        return reward;
    }

    // 设置奖励代币实例
    function setRewardToken(address _rewardToken) external onlyOwner {
        rewardToken = IERC20(_rewardToken);
    }

    // 设置项目质押开始时间
    function setStakingStartTime(uint256 _stakingStartTime) external onlyOwner {
        totalStake = 0;
        stakingStartTime = _stakingStartTime;
    }

      // 设置项目锁仓时间
    function setLockupPeriod(uint256 _lockupPeriod) external onlyOwner {
        lockupPeriod = _lockupPeriod;
    }
    // 设置年华收益率
    function setRewardRateInit(uint256 _rewardRateInit) external onlyOwner {
        rewardRateInit = _rewardRateInit;
    }
      // 查询用户的余额
    function balanceOf(address _address) external view returns (uint256){
        return stakingBalance[_address];
    }

    // 新增：设置质押总量上限
    function setStakingCap(uint256 _stakingCap) external onlyOwner {
        stakingCap = _stakingCap;
    }
    // 新增：设置最小质押数量
    function setMinStakeAmount(uint256 _minStakeAmount) external onlyOwner {
        minStakeAmount = _minStakeAmount;
    }

    // 新增：用户确认重新质押
    function confirmRestake() external nonReentrant whenNotPaused{
        require(stakingBalance[msg.sender] > 0, "The user's staking balance is zero");
        require(stakingTime[msg.sender]<stakingStartTime,"User has not participated in previous staking activities");
        require(block.timestamp < stakingStartTime + lockupPeriod, "The current staking event has ended");

        // 用户 之前质押的余额 + 用户 之前的质押收益 = 新的质押余额
        uint256 previousAmount =  stakingBalance[msg.sender];
        uint256 previousReward =  stakingReward[msg.sender];
        uint256 compoundAmount = previousAmount+previousReward;

        require(totalStake + compoundAmount <= stakingCap, "Staking cap exceeded");

        stakingTime[msg.sender] = block.timestamp;
        uint256 reward = getRewardForUser(msg.sender,compoundAmount);
        stakingReward[msg.sender] =previousReward + reward;
        totalStake = totalStake + compoundAmount;
        totalReward = totalReward + reward;
        emit Stake(msg.sender, compoundAmount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
}
