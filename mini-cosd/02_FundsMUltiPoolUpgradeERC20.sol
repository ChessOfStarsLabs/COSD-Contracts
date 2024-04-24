// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract FundsMUltiPoolUpgradeERC20V2 is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    struct Pool {
        uint256 maxPlayers;                       // 池中的最大玩家数
        uint256 minAmount;                        // 参与资金盘的最小金额
        uint256[] rewardPercentage;               // 获奖者比例信息
        mapping(uint => Round) rounds;
        uint roundsCount;
    }

    struct Round {
        uint256 totalFund;
        uint256 totalPlayers;
        address[] playerAddresses;
    }

    struct playerReward {
        uint poolIndex;
        uint256 roundIndex;
        uint256 reward;
    }

    IERC20 public token;

    Pool[] public pools;

    // 获奖者的历史奖励
    mapping(address => playerReward[]) public roundRewards;
    // 表示获奖者是是否在 在这一轮资金盘中
    mapping(uint => mapping(uint => mapping(address => bool))) public isPlayerParticipatedInRound;
    // 标识奖励是否已经分配完毕，防止重复分配
    mapping(uint => mapping(uint => bool)) public finishPayout;

    // 某一获奖者在某个池子中的总奖励
    mapping(uint => mapping(address => uint256)) public rewards;
    // 某一池子的总奖励
    mapping(uint => uint256) public totalRewards;

    // 获奖者的总奖励
    mapping(address => uint256) public userRewards;

    // 操作员
    mapping(address => bool) public operator;

    event RoundFinished(uint256 indexed poolIndex, uint256 indexed roundIndex, address[] playerAddresses, uint256 totalFund);
    event RoundPending(uint256 indexed poolIndex, uint256 indexed roundIndex, address playerAddresses, uint256 value);
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address _tokenAddress,  uint256[] memory _maxPlayers, uint256[][] memory _rewardPercentage, uint256[] memory _minAmounts) initializer public {
        token = IERC20(_tokenAddress);

        operator[msg.sender] = true;
        for (uint i = 0; i < _minAmounts.length; i++) {
            pools.push();
            uint poolIndex = pools.length - 1;

            pools[poolIndex].minAmount = _minAmounts[i];
            pools[poolIndex].maxPlayers = _maxPlayers[i];
            pools[poolIndex].rewardPercentage = _rewardPercentage[i];
            pools[poolIndex].roundsCount = 1;
        }
        // 初始化 ReentrancyGuard
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    function deposit(uint poolIndex, uint256 amount) external nonReentrant whenNotPaused {
        require(poolIndex < pools.length, "Invalid pool index");

        Pool storage pool = pools[poolIndex];
        Round storage currentRound = pool.rounds[pool.roundsCount];

        require(currentRound.totalPlayers < pool.maxPlayers, "Round already full");
        require(amount >= pools[poolIndex].minAmount, "Need more currency");
        token.safeTransferFrom(msg.sender, address(this), amount);


        currentRound.playerAddresses.push(msg.sender);
        currentRound.totalFund += amount;
        currentRound.totalPlayers++;
        isPlayerParticipatedInRound[poolIndex][pool.roundsCount][msg.sender] = true;

        emit RoundPending(poolIndex, pool.roundsCount, msg.sender, amount);

        if (currentRound.totalPlayers == pool.maxPlayers) {
            emit RoundFinished(poolIndex, pool.roundsCount, currentRound.playerAddresses, currentRound.totalFund);
            pool.roundsCount++;
        }
    }

    function payout(uint poolIndex, uint256 roundIndex,address[] memory winnerAddresses) external whenNotPaused {

        require(operator[msg.sender], "Permission denied");
        require(poolIndex < pools.length, "Invalid pool index");
        require(roundIndex < pools[poolIndex].roundsCount, "Invalid round index");
        require(!finishPayout[poolIndex][roundIndex], "Round already finished");

        Round storage round = pools[poolIndex].rounds[roundIndex];
        Pool storage pool = pools[poolIndex];


        require(round.totalPlayers == pool.maxPlayers, "Round not finished yet");

        require(winnerAddresses.length == pool.rewardPercentage.length, "Incorrect number of winners");

        uint256 currentRoundReward;

        for (uint i = 0; i < winnerAddresses.length; i++) {
            require(isPlayerParticipatedInRound[poolIndex][roundIndex][winnerAddresses[i]], "the winner address didn't participate in the round");
            address winnerAddress = winnerAddresses[i];
            uint256 rewardPercentage = pool.rewardPercentage[i];
            currentRoundReward+=_distributeReward(poolIndex, roundIndex, winnerAddress, rewardPercentage);
        }

        finishPayout[poolIndex][roundIndex] = true;
        round.totalFund = round.totalFund - currentRoundReward;
    }

    function _distributeReward(uint poolIndex, uint256 roundIndex, address winner, uint256 rewardPercentage) internal returns (uint256) {
        Round storage round = pools[poolIndex].rounds[roundIndex];
        uint256 rewardAmount = round.totalFund * rewardPercentage / 10000;
        rewards[poolIndex][winner] += rewardAmount;
        totalRewards[poolIndex] += rewardAmount;
        roundRewards[winner].push(playerReward(poolIndex, roundIndex, rewardAmount));
        userRewards[winner] += rewardAmount;
        return rewardAmount;
    }

    function getRewardsByOwner(address owner) view public returns (playerReward[] memory) {
        return roundRewards[owner];
    }

    function getRound(uint poolIndex, uint roundIndex) view public returns (uint256 totalFund, uint256 totalPlayers, address[] memory playerAddresses) {
        Round storage round = pools[poolIndex].rounds[roundIndex];
        return (round.totalFund, round.totalPlayers, round.playerAddresses);
    }

    function withdraw() external nonReentrant whenNotPaused {
        require(userRewards[msg.sender] > 0, "No reward available");
        token.safeTransfer(msg.sender, userRewards[msg.sender]);
        userRewards[msg.sender] = 0;
    }


    function withdrawRemaining(address payable recipient) external onlyOwner {
        uint256 remainingBalance = token.balanceOf(address(this));
        require(remainingBalance > 0, "No remaining funds");

        uint256 totalPoolRewards = 0;
        for (uint i = 0; i < pools.length; i++) {
            totalPoolRewards += totalRewards[i];
        }

        uint256 transferAmount = remainingBalance - totalPoolRewards;
        token.safeTransfer(recipient, transferAmount);
    }
    // 修改当前 质押游戏 的 round
    function setPoolRoundCount(uint poolIndex, uint roundCount) external onlyOwner {
        Pool storage pool = pools[poolIndex];
        pool.roundsCount = roundCount;
    }
    // 开设一个新的质押游戏
    function setNewPool(uint256 _maxPlayers, uint256[] memory _rewardPercentage, uint256 _minAmounts) external onlyOwner {
        pools.push();
        uint poolIndex = pools.length - 1;

        pools[poolIndex].minAmount = _minAmounts;
        pools[poolIndex].maxPlayers = _maxPlayers;
        pools[poolIndex].rewardPercentage = _rewardPercentage;
        pools[poolIndex].roundsCount = 1;
    }

    function addOperator(address _operator) public onlyOwner {
        operator[_operator] = true;
    }
    function removeOperator(address _operator) public onlyOwner {
        operator[_operator] = false;
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
