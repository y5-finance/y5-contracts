// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "./libs/ERC20.sol";
import "./libs/IUniswapV2Router02.sol";
import "./libs/IUniswapV2Factory.sol";
import "./libs/IUniswapV2Pair.sol";

contract Y5Finance is ERC20("Y-5 Finance", "Y-5", 18) {
    using SafeMath for uint256;
    using Address for address;

    address payable public _marketingAddress; // Marketing Address
    address public constant DEAD_ADDRESS =
        0x000000000000000000000000000000000000dEaD;
    uint256 public constant TAX_UPPER_LIMIT = 3000; // Token transfer tax upper limit - 30%
    uint256 public constant MAX_TX_AMOUNT_LOWER_LIMIT = 1000 ether; // Max transferable amount should be over 1000 tokens
    address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address public constant EGC = 0xC001BBe2B87079294C63EcE98BdD0a88D761434e;
    address public constant REFLECTO =
        0xEA3C823176D2F6feDC682d3cd9C30115448767b3;
    address public constant CRYPT = 0xDa6802BbEC06Ab447A68294A63DE47eD4506ACAA;
    address public constant RMTX = 0x0c01099f3d4c920504E577bd7617F0D7c53cD8Df;

    // Info of each holder
    struct HolderInfo {
        uint256 earned; // Total earned
        uint256 rewardDebt; // Reward Debt
    }

    // Info of each rewards
    struct RewardInfo {
        uint256 accRewardPerShare; // Accumulated rewards per share, times 10**(30-decimals)
        uint256 distributed; // Total distributed to the holders
        uint256 toDistribute; // Available to be distributed to the holders
    }

    /** Reflection reward variables **/
    mapping(address => mapping(address => HolderInfo)) public _holderInfo;
    mapping(address => RewardInfo) public _rewardInfo;

    /** Fee variables **/
    uint256 public _reflectionFee;
    uint256 private _previousReflectionFee;
    uint256 public _liquidityFee;
    uint256 private _previousLiquidityFee;
    uint256 public _buybackFee;
    uint256 private _previousBuybackFee;
    uint256 public _marketingFee;
    uint256 private _previousMarketingFee;
    mapping(address => bool) private _isExcludedFromFee;

    /** Unti-whales feature **/
    uint256 public _maxTxAmount;
    uint256 private _previousMaxTxAmount;

    uint256 private _minimumTokensBeforeSwap;
    uint256 private _buyBackLowerLimit;
    uint256 private _buyBackUpperLimit;
    bool private _inSwapAndLiquify;
    bool public _swapAndLiquifyEnabled = true;
    bool public _buyBackEnabled = true;
    bool public _tokenNormalized = false;

    IUniswapV2Router02 public immutable _uniswapV2Router;
    address public immutable _y5EtherPair;
    address public immutable _y5BusdPair;
    address public immutable _y5EgcPair;
    address public immutable _y5ReflectoPair;
    address public immutable _y5CryptPair;
    address public immutable _y5RmtxPair;

    /** Events **/
    event RewardLiquidityProviders(uint256 tokenAmount);
    event BuyBackEnabledUpdated(address indexed ownerAddress, bool enabled);
    event SwapAndLiquifyEnabledUpdated(
        address indexed ownerAddress,
        bool enabled
    );
    event SwapETHForTokens(uint256 amountIn, address[] path);
    event SwapTokensForETH(uint256 amountIn, address[] path);
    event SwapTokensForTokens(uint256 amountIn, address[] path);
    event ExcludedFromFee(
        address indexed ownerAddress,
        address indexed accountAddress
    );
    event IncludedFromFee(
        address indexed ownerAddress,
        address indexed accountAddress
    );
    event ReflectionFeeUpdated(
        address indexed ownerAddress,
        uint256 oldFee,
        uint256 newFee
    );
    event BuybackFeeUpdated(
        address indexed ownerAddress,
        uint256 oldFee,
        uint256 newFee
    );
    event MarketingFeeUpdated(
        address indexed ownerAddress,
        uint256 oldFee,
        uint256 newFee
    );
    event LiquidityFeeUpdated(
        address indexed ownerAddress,
        uint256 oldFee,
        uint256 newFee
    );
    event MaxTxAmountUpdated(
        address indexed ownerAddress,
        uint256 oldAmount,
        uint256 newAmount
    );
    event BuybackUpperLimitUpdated(
        address indexed ownerAddress,
        uint256 oldLimit,
        uint256 newLimit
    );
    event BuybackLowerLimitUpdated(
        address indexed ownerAddress,
        uint256 oldLimit,
        uint256 newLimit
    );
    event MarketingAddressUpdated(
        address indexed ownerAddress,
        address indexed oldAddress,
        address indexed newAddress
    );
    event TokenNormalized(address indexed ownerAddress, bool enabled);
    event UserRewardsClaimed(
        address indexed userAddress,
        address indexed tokenAddress,
        uint256 amount
    );

    modifier lockTheSwap() {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    constructor() {
        _marketingAddress = payable(0xBCee8EDCc76D72022206FAE4Be3F80aadBB5770C);
        _mint(_marketingAddress, 10**15 * 10**decimals());

        _reflectionFee = 1300;
        _previousReflectionFee = _reflectionFee;
        _buybackFee = 400;
        _previousBuybackFee = _buybackFee;
        _marketingFee = 200;
        _previousMarketingFee = _marketingFee;
        _liquidityFee = 100;
        _previousLiquidityFee = _liquidityFee;

        _maxTxAmount = totalSupply().div(1000); // initial max transferable amount 0.1%
        _previousMaxTxAmount = _maxTxAmount;

        _minimumTokensBeforeSwap = 1000 ether;
        _buyBackLowerLimit = 1 ether;
        _buyBackUpperLimit = 100 ether;

        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );
        _y5EtherPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        _y5BusdPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            BUSD
        );
        _y5EgcPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            EGC
        );
        _y5ReflectoPair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), REFLECTO);
        _y5CryptPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            CRYPT
        );
        _y5RmtxPair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            RMTX
        );
        _uniswapV2Router = uniswapV2Router;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    function isExcludedFromFee(address account) external view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function excludeFromFee(address account) external onlyOwner {
        if (_isExcludedFromFee[account] == false) {
            _isExcludedFromFee[account] = true;
            emit ExcludedFromFee(owner(), account);
        }
    }

    function includeInFee(address account) external onlyOwner {
        if (_isExcludedFromFee[account]) {
            _isExcludedFromFee[account] = false;
            emit IncludedFromFee(owner(), account);
        }
    }

    function setReflectionFee(uint256 reflectionFee) external onlyOwner {
        uint256 taxFee = reflectionFee.add(_buybackFee).add(_marketingFee).add(
            _liquidityFee
        );
        require(taxFee <= TAX_UPPER_LIMIT, "Y-5: transfer tax exceeds limit");
        if (_reflectionFee != reflectionFee) {
            emit ReflectionFeeUpdated(owner(), _reflectionFee, reflectionFee);
            _reflectionFee = reflectionFee;
        }
    }

    function setBuybackFee(uint256 buybackFee) external onlyOwner {
        uint256 taxFee = buybackFee.add(_reflectionFee).add(_marketingFee).add(
            _liquidityFee
        );
        require(taxFee <= TAX_UPPER_LIMIT, "Y-5: transfer tax exceeds limit");
        if (_buybackFee != buybackFee) {
            emit BuybackFeeUpdated(owner(), _buybackFee, buybackFee);
            _buybackFee = buybackFee;
        }
    }

    function setMarketingFee(uint256 marketingFee) external onlyOwner {
        uint256 taxFee = marketingFee.add(_reflectionFee).add(_buybackFee).add(
            _liquidityFee
        );
        require(taxFee <= TAX_UPPER_LIMIT, "Y-5: transfer tax exceeds limit");
        if (_marketingFee != marketingFee) {
            emit MarketingFeeUpdated(owner(), _marketingFee, marketingFee);
            _marketingFee = marketingFee;
        }
    }

    function setLiquidityFee(uint256 liquidityFee) external onlyOwner {
        uint256 taxFee = liquidityFee.add(_reflectionFee).add(_buybackFee).add(
            _marketingFee
        );
        require(taxFee <= TAX_UPPER_LIMIT, "Y-5: transfer tax exceeds limit");
        if (_liquidityFee != liquidityFee) {
            emit LiquidityFeeUpdated(owner(), _liquidityFee, liquidityFee);
            _liquidityFee = liquidityFee;
        }
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        require(
            maxTxAmount >= MAX_TX_AMOUNT_LOWER_LIMIT,
            "Y-5: maxTxAmount should be over 1000 tokens"
        );
        if (_maxTxAmount != maxTxAmount) {
            emit MaxTxAmountUpdated(owner(), _maxTxAmount, maxTxAmount);
            _maxTxAmount = maxTxAmount;
        }
    }

    function minimumTokensBeforeSwapAmount() public view returns (uint256) {
        return _minimumTokensBeforeSwap;
    }

    function buyBackLowerLimitAmount() public view returns (uint256) {
        return _buyBackLowerLimit;
    }

    function buyBackUpperLimitAmount() public view returns (uint256) {
        return _buyBackUpperLimit;
    }

    function setNumTokensSellToAddToLiquidity(uint256 minimumTokensBeforeSwap)
        external
        onlyOwner
    {
        _minimumTokensBeforeSwap = minimumTokensBeforeSwap;
    }

    function setBuybackLowerLimit(uint256 lowerLimit) external onlyOwner {
        if (_buyBackLowerLimit != lowerLimit) {
            emit BuybackLowerLimitUpdated(
                owner(),
                _buyBackLowerLimit,
                lowerLimit
            );
            _buyBackLowerLimit = lowerLimit;
        }
    }

    function setBuybackUpperLimit(uint256 upperLimit) external onlyOwner {
        if (_buyBackUpperLimit != upperLimit) {
            emit BuybackUpperLimitUpdated(
                owner(),
                _buyBackUpperLimit,
                upperLimit
            );
            _buyBackUpperLimit = upperLimit;
        }
    }

    function setMarketingAddress(address marketingAddress) external onlyOwner {
        require(
            _marketingAddress != address(0),
            "Y-5: marketing address can not be zero address"
        );
        if (_marketingAddress != marketingAddress) {
            emit MarketingAddressUpdated(
                owner(),
                _marketingAddress,
                marketingAddress
            );
            _marketingAddress = payable(marketingAddress);
        }
    }

    function setSwapAndLiquifyEnabled(bool enabled) public onlyOwner {
        if (_swapAndLiquifyEnabled != enabled) {
            _swapAndLiquifyEnabled = enabled;
            emit SwapAndLiquifyEnabledUpdated(owner(), enabled);
        }
    }

    function setBuyBackEnabled(bool enabled) external onlyOwner {
        if (_buyBackEnabled != enabled) {
            _buyBackEnabled = enabled;
            emit BuyBackEnabledUpdated(owner(), enabled);
        }
    }

    function removeAllFee() private {
        if (
            _reflectionFee == 0 &&
            _liquidityFee == 0 &&
            _marketingFee == 0 &&
            _buybackFee == 0
        ) return;

        _previousReflectionFee = _reflectionFee;
        _previousLiquidityFee = _liquidityFee;
        _previousBuybackFee = _buybackFee;
        _previousMarketingFee = _marketingFee;

        _reflectionFee = 0;
        _liquidityFee = 0;
        _buybackFee = 0;
        _marketingFee = 0;
    }

    function restoreAllFee() private {
        _reflectionFee = _previousReflectionFee;
        _liquidityFee = _previousLiquidityFee;
        _buybackFee = _previousBuybackFee;
        _marketingFee = _previousMarketingFee;
    }

    function normalizeToken(bool enabled) external onlyOwner {
        if (_tokenNormalized != enabled) {
            if (enabled) {
                setSwapAndLiquifyEnabled(false);
                removeAllFee();
                _previousMaxTxAmount = _maxTxAmount;
                _maxTxAmount = totalSupply();
            } else {
                setSwapAndLiquifyEnabled(true);
                restoreAllFee();
                _maxTxAmount = _previousMaxTxAmount;
            }
            _tokenNormalized = enabled;
            emit TokenNormalized(owner(), enabled);
        }
    }

    function transferToAddressETH(address payable recipient, uint256 amount)
        private
    {
        recipient.transfer(amount);
    }

    function withdrawETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function pendingRewards(address user, address tokenAddress)
        public
        view
        returns (uint256)
    {
        uint256 accRewardPerShare = _rewardInfo[tokenAddress].accRewardPerShare;
        uint256 rewardDebt = _holderInfo[user][tokenAddress].rewardDebt;
        uint256 userTokenBalance = balanceOf(user);
        IERC20 token = IERC20(tokenAddress);
        return
            userTokenBalance
                .mul(accRewardPerShare)
                .div(10**(30 - token.decimals()))
                .sub(rewardDebt);
    }

    function claimRewards(address tokenAddress) external {
        uint256 pending = pendingRewards(msg.sender, tokenAddress);
        IERC20 token = IERC20(tokenAddress);
        HolderInfo storage holderInfo = _holderInfo[msg.sender][tokenAddress];
        RewardInfo storage rewardInfo = _rewardInfo[tokenAddress];
        if (pending > 0 && token.balanceOf(address(this)) > 0) {
            if (pending > token.balanceOf(address(this))) {
                pending = token.balanceOf(address(this));
            }
            token.transfer(msg.sender, pending);
            holderInfo.earned = holderInfo.earned.add(pending);
            rewardInfo.distributed = rewardInfo.distributed.add(pending);
            rewardInfo.toDistribute = rewardInfo.toDistribute.sub(pending);
            emit UserRewardsClaimed(msg.sender, tokenAddress, pending);
        }
        holderInfo.rewardDebt = balanceOf(msg.sender)
            .mul(_rewardInfo[msg.sender].accRewardPerShare)
            .div(10**(30 - token.decimals()));
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Y-5: transfer amount must be greater than zero");
        if (from != owner() && to != owner()) {
            require(
                amount <= _maxTxAmount,
                "Y-5: transfer amount exceeds the maxTxAmount."
            );
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool overMinimumTokenBalance = contractTokenBalance >=
            _minimumTokensBeforeSwap;

        if (
            !_inSwapAndLiquify &&
            _swapAndLiquifyEnabled &&
            (to == _y5EtherPair ||
                to == _y5BusdPair ||
                to == _y5EgcPair ||
                to == _y5ReflectoPair ||
                to == _y5CryptPair ||
                to == _y5RmtxPair)
        ) {
            if (overMinimumTokenBalance) {
                contractTokenBalance = _minimumTokensBeforeSwap;
                swapTokens(contractTokenBalance);
            }
            uint256 balance = address(this).balance;
            if (_buyBackEnabled && balance >= _buyBackLowerLimit) {
                if (balance > _buyBackUpperLimit) balance = _buyBackUpperLimit;

                buyBackTokens(balance);
            }
        }

        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    function swapTokens(uint256 tokenBalance) private lockTheSwap {
        uint256 taxFee = _reflectionFee.add(_buybackFee).add(_marketingFee).add(
            _liquidityFee
        );
        if (taxFee == 0) {
            return;
        }

        uint256 reflectionBalance = tokenBalance.mul(_reflectionFee).div(
            taxFee
        );
        uint256 liquidityBalance = tokenBalance.mul(_liquidityFee).div(taxFee);
        uint256 buybackAndMarketingBalance = tokenBalance
            .sub(reflectionBalance)
            .sub(liquidityBalance);

        // swap token to ether for buyback and marketing
        if (
            buybackAndMarketingBalance > 0 && _marketingFee.add(_buybackFee) > 0
        ) {
            uint256 balanceBefore = address(this).balance;
            swapTokensForEth(buybackAndMarketingBalance);
            uint256 swappedBalance = address(this).balance.sub(balanceBefore);

            //Send marketing fee to the marketing address, buyback fee will be remained in the token contract to buy tokens back later
            uint256 marketingFeeAmount = swappedBalance.mul(_marketingFee).sub(
                _marketingFee.add(_buybackFee)
            );
            if (marketingFeeAmount > 0) {
                transferToAddressETH(_marketingAddress, marketingFeeAmount);
            }
        }

        // add liquidity
        if (liquidityBalance.div(2) > 0) {
            uint256 balanceBefore = address(this).balance;
            swapTokensForEth(liquidityBalance.div(2));
            uint256 swappedBalance = address(this).balance.sub(balanceBefore);
            addLiquidity(liquidityBalance.div(2), swappedBalance);
        }

        // reflect to the holders, distributed by 5 tokens
        if (reflectionBalance.div(5) > 0) {
            swapTokensForTokens(reflectionBalance.div(5), BUSD);
            swapTokensForTokens(reflectionBalance.div(5), EGC);
            swapTokensForTokens(reflectionBalance.div(5), REFLECTO);
            swapTokensForTokens(reflectionBalance.div(5), CRYPT);
            swapTokensForTokens(reflectionBalance.div(5), RMTX);
        }
    }

    function buyBackTokens(uint256 amount) private lockTheSwap {
        if (amount > 0) {
            swapETHForTokens(amount);
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();

        _approve(address(this), address(_uniswapV2Router), tokenAmount);

        // make the swap
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );

        emit SwapTokensForETH(tokenAmount, path);
    }

    function swapTokensForTokens(uint256 tokenAmount, address toTokenAddress)
        private
    {
        // generate the uniswap pair path of token -> toToken
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = toTokenAddress;

        _approve(address(this), address(_uniswapV2Router), tokenAmount);

        // make the swap
        IERC20 toToken = IERC20(toTokenAddress);
        uint256 balanceBefore = toToken.balanceOf(address(this));
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of toToken
            path,
            address(this), // The contract
            block.timestamp
        );
        uint256 swappedBalance = toToken.balanceOf(address(this)).sub(
            balanceBefore
        );

        // total rewarded amounts
        RewardInfo storage rewardInfo = _rewardInfo[toTokenAddress];
        rewardInfo.toDistribute = rewardInfo.toDistribute.add(swappedBalance);

        // update reward per share
        rewardInfo.accRewardPerShare = rewardInfo.accRewardPerShare.add(
            swappedBalance.mul(10**(30 - toToken.decimals())).div(totalSupply())
        );

        emit SwapTokensForTokens(tokenAmount, path);
    }

    function swapETHForTokens(uint256 amount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = _uniswapV2Router.WETH();
        path[1] = address(this);

        // make the swap
        _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(
            0, // accept any amount of Tokens
            path,
            DEAD_ADDRESS, // Burn address
            block.timestamp.add(300)
        );

        emit SwapETHForTokens(amount, path);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_uniswapV2Router), tokenAmount);

        // add the liquidity
        _uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            _marketingAddress,
            block.timestamp
        );
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        uint256 feeAmount = 0;
        if (takeFee) {
            uint256 taxFee = _reflectionFee
                .add(_marketingFee)
                .add(_liquidityFee)
                .add(_buybackFee);
            feeAmount = amount.mul(taxFee).div(10000);
        }
        amount = amount.sub(feeAmount);
        if (amount > 0) {
            super._transfer(sender, recipient, amount);
        }
        if (feeAmount > 0) {
            super._transfer(sender, address(this), feeAmount);
        }
    }
}
