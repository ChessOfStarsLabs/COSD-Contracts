// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract BuyTokenContractV2 is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    // USDT 合约实例
    IERC20 public usdt;
    // 自定义代币合约实例
    IERC20 public myToken;
    // 兑换比例
    uint256 public exchangeRate;

    // 设置每个用户的最大购买量
    uint256 public maxAmout;
    // 记录用户的购买量
    mapping(address => uint256) public cumulativePurchase;

    // 代币的价格（USDT），支持6位小数字，比如一枚 COSD 的价格是0.7 usdt，那么price=700000
    uint256 public price;
    uint256 internal constant _PRICE_DECIMALS = 6;



    event BuyToken(address indexed user, uint256 usdtAmount,uint256 tokenAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner,address _usdtAddress,address _tokenAddress,uint256 _exchangeRate,uint256 _maxAmout) initializer public {
        usdt = IERC20(_usdtAddress);
        myToken = IERC20(_tokenAddress);
        exchangeRate = _exchangeRate;
        maxAmout = _maxAmout;
        // 初始化 ReentrancyGuard
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }
    function buyToken(uint256 _usdtAmount) external nonReentrant{
        uint256 tokenAmount = _usdtAmount * (10**_PRICE_DECIMALS) / price;
        require(maxAmout >= cumulativePurchase[msg.sender] + tokenAmount,"A single user cannot buy too many tokens");
        require(myToken.balanceOf(address(this))>=tokenAmount,"The number of tokens that users need to purchase exceeds the number of tokens currently available for purchase");
        require(usdt.balanceOf(msg.sender) >= _usdtAmount, "Not enough USDT");
        usdt.safeTransferFrom(msg.sender, address(this), _usdtAmount);
        myToken.safeTransfer(msg.sender, tokenAmount);
        cumulativePurchase[msg.sender] = cumulativePurchase[msg.sender] + tokenAmount;
        emit BuyToken(msg.sender, _usdtAmount,tokenAmount);

    }

    // 合约所有者可从合约中提取 USDT
    function withdrawUSDT(uint256 amount) external onlyOwner{
        require(usdt.balanceOf(address(this))>=amount,"Amount is greater than the balance of contract");
        usdt.safeTransfer(owner(), amount);
    }

    // 更改兑换比例
    function setExchangeRate(uint256 _exchangeRate) external onlyOwner{
        exchangeRate = _exchangeRate;
    }

    // 设置价格
    function setPrice(uint256 _price) external onlyOwner{
        price = _price;
    }
    // 更改每个用户的最大购买量
    function setMaxAmout(uint256 _maxAmount) external onlyOwner{
        maxAmout = _maxAmount;
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
