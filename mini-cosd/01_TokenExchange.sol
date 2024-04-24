// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract TokenExchangeContract is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    // USDT 合约实例
    IERC20 public usdt;
    // 自定义代币合约实例
    IERC20 public myToken;
    // 兑换比例
    uint256 public exchangeRate;

    event BuyToken(address indexed user, uint256 usdtAmount,uint256 tokenAmount);
    event SellToken(address indexed user, uint256 tokenAmount,uint256 usdtAmount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner,address _usdtAddress,address _tokenAddress,uint256 _exchangeRate) initializer public {
        usdt = IERC20(_usdtAddress);
        myToken = IERC20(_tokenAddress);
        exchangeRate = _exchangeRate;
        // 初始化 ReentrancyGuard
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }
    function buyToken(uint256 _usdtAmount) external nonReentrant{
        uint256 tokenAmount = _usdtAmount * exchangeRate;
        require(myToken.balanceOf(address(this))>=tokenAmount,"The number of tokens that users need to purchase exceeds the number of tokens currently available for purchase");
        require(usdt.balanceOf(msg.sender) >= _usdtAmount, "Not enough USDT");
        usdt.safeTransferFrom(msg.sender, address(this), _usdtAmount);
        myToken.safeTransfer(msg.sender, tokenAmount);
        emit BuyToken(msg.sender, _usdtAmount,tokenAmount);
    }

    function sellToken(uint256 _tokenAmount) external nonReentrant{
        uint256 usdtAmount = (_tokenAmount + exchangeRate/2) / exchangeRate;
        require(usdt.balanceOf(address(this))>=usdtAmount,"The number of usdt that users want to exchange exceeds the number of usdt currently available for exchange");
        require(myToken.balanceOf(msg.sender) >= _tokenAmount, "Not enough token");
        myToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        usdt.safeTransfer(msg.sender, usdtAmount);
        emit SellToken(msg.sender, _tokenAmount, usdtAmount);
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
