// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
import "./AntiWhale.sol";
import "./WhiteList.sol";
import "./BlackList.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// TODO: мультиподпись - несколько владельцев контракта - коллективное управление контракт
// TODO: добавить функцию с приватным списком адресов для эйрдропа и инфлюенсерам
// TODO: функция эйрдопа
// TODO: Токенсейл, если мы недошли до хардкепа, то снимает
// TODO: нужен смарт-контракт для Вайтлиста
// TODO: контракт для отсекания по адресам, по времени (в минуту 3 транзакции) + включаемая и отключаемая функция, примерно 3 транзакции в минуту

// взаимодействие с Панкейком
contract UnnamedToken is Context, IERC20, WhiteList, BlackList {
    using SafeMath for uint256;

    address _whiteList;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => uint256) private _transactionCheckpoint;
    mapping(address => bool) public _isExcludedFromAntiWhale;
    mapping(address => bool) public _isExcludeFromExternalTokenMinAmount;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _isBlacklisted;
    mapping(address => bool) private _isExcludedFromTransactionlock;
    mapping(address => bool) private _isExcludedFromMaxTxAmount;

    address[] private _excluded;
    address public immutable uniswapV2Pair;
    address public pancakePair;
    address payable public _externalAddress =
        payable(0x50C7f291916e1CAFf2601eE82D398D5841f37793);
    address payable public _burnAddress =
        payable(0x000000000000000000000000000000000000dEaD);

    string private _name = "Unnamed";
    string private _symbol = "UNN";
    uint8 private _decimals = 18;
    uint256 private _tFeeTotal;
    uint256 public _taxFee = 5;
    uint256 public _liquidityFee = 5; // uint256 public _liquidityFee = 60;

    IUniswapV2Router02 public immutable uniswapV2Router;

    bool inSwapAndLiquify;
    bool public isExternalTokenHoldEnabled;
    bool public swapAndLiquifyEnabled = true;

    uint256 private constant MAX = ~uint256(0);
    uint256 constant maxCap = 1000000000 * (10**18);
    uint256 private _rTotal = (MAX - (MAX % maxCap));
    uint256 public _maxTxAmount = 12500 * 10**6 * 10**9;
    uint256 private _totalSupply = maxCap;
    uint256 private _lockTime;
    // uint256 private _tFeeTotal;
    uint256 public _burnFee = 0;
    uint256 private _previousBurnFee = _burnFee;
    uint256 public _reflectionFee = 100;
    uint256 private _previousReflectionFee = _reflectionFee;
    uint256 public _externalFee = 90;
    uint256 private _previousExternalFee = _externalFee;
    uint256 private _previousLiquidityFee = _liquidityFee;
    uint256 private _totalLiquidityFee = _externalFee.add(_liquidityFee);
    uint256 private _previousTLiquidityFee = _totalLiquidityFee;
    uint256 private _transactionLockTime = 0;
    uint256 public _externalTokenMinAmount = 50000 * 10**6 * 10**_decimals;
    uint256 public _maxTxAmountBuy = 1000000 * 10**6 * 10**_decimals;
    uint256 public _maxTxAmountSell = 1000000 * 10**6 * 10**_decimals;
    uint256 public _numTokensSellToAndTransfer = 500000 * 10**6 * 10**_decimals;
    uint256 public _maxTokensPerAddress = 20000000 * 10**6 * 10**_decimals;

    IERC20 public _externalToken; // OR IBEP

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    // на ВЛ - 15 %
    constructor(address _wL) {
        // _balances[msg.sender] = maxCap - (maxCap / 100) * 15;
        // _balances[_wL] = (maxCap / 100) * 15;

        _balances[msg.sender] = maxCap;

        // 1 этап - для попаданяи в вайт лист нуэнго удовлетворить условиям, из вайтлиста выбирается количество адресов. которые будут участвовать в Сейле
        // 1,5 этап - на фонд ейрдорпа кидается 5%
        // 2 этап - токен сеейл, по участникам ВайтЛиста?
        // 3 этап - после хардкапа -  распределение токенов (20% по ВайтЛисту)
        // 4 этап - на листинге 1% аэрдорпа распределятся из фонда Эйрдропа
        // На момент распределение токенов нужно отключить дефялционную модель (рапсред 5%)

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );

        // Create a pancakeswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_externalAddress] = true;

        _isExcludedFromTransactionlock[owner()] = true;
        _isExcludedFromTransactionlock[address(this)] = true;
        _isExcludedFromTransactionlock[pancakePair] = true;
        _isExcludedFromTransactionlock[address(_uniswapV2Router)] = true;
        _isExcludedFromTransactionlock[_burnAddress] = true;

        _isExcludeFromExternalTokenMinAmount[owner()] = true;
        _isExcludeFromExternalTokenMinAmount[address(this)] = true;
        _isExcludeFromExternalTokenMinAmount[pancakePair] = true;
        _isExcludeFromExternalTokenMinAmount[address(_uniswapV2Router)] = true;
        _isExcludeFromExternalTokenMinAmount[_burnAddress] = true;

        _isExcludedFromMaxTxAmount[owner()] = true;
        _isExcludedFromMaxTxAmount[address(this)] = true;
        _isExcludedFromMaxTxAmount[pancakePair] = true;
        _isExcludedFromMaxTxAmount[address(_uniswapV2Router)] = true;
        _isExcludedFromMaxTxAmount[_burnAddress] = true;

        _isExcludedFromAntiWhale[owner()] = true;
        _isExcludedFromAntiWhale[address(this)] = true;
        _isExcludedFromAntiWhale[pancakePair] = true;
        _isExcludedFromAntiWhale[address(_uniswapV2Router)] = true;
        _isExcludedFromAntiWhale[_burnAddress] = true;

        _isExcluded[address(0)] = true;
        _isExcluded[_burnAddress] = true;
    }

    // TODO: функции распределения Токенов участникам ВЛ согласно проценту их учасития (0,5 - 3 BNB)

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    // часть сжигается(1,5%), часть уходит в ликвидность(2%), холдерам(1.5%)
    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner {
        _taxFee = taxFee;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        _approve(sender, _msgSender(), currentAllowance.sub(amount));

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(10**2);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    // нужно часть переводить другим - нужно чтобы это можно было отключить
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            _isExcludedFromAntiWhale[recipient] ||
                balanceOf(recipient) + amount <= _maxTokensPerAddress,
            "Max tokens limit for this account reached. Or try lower amount"
        );
        require(!_isBlacklisted[sender], "You are banned");
        require(!_isBlacklisted[recipient], "The recipient is banned");
        require(
            _isExcludedFromTransactionlock[sender] ||
                block.timestamp - _transactionCheckpoint[sender] >=
                _transactionLockTime,
            "Please wait for transaction cooldown time to finish"
        );
        require(
            _isExcludedFromTransactionlock[recipient] ||
                block.timestamp - _transactionCheckpoint[recipient] >=
                _transactionLockTime,
            "Please wait for recepients transaction cooldown time to finish"
        );
        if (sender == pancakePair) {
            if (isExternalTokenHoldEnabled)
                require(
                    _isExcludeFromExternalTokenMinAmount[recipient] ||
                        _externalToken.balanceOf(recipient) >=
                        _externalTokenMinAmount,
                    "Must hold minimum amount of External tokens to buy this tokens"
                );
            if (!_isExcludedFromMaxTxAmount[recipient])
                require(
                    amount <= _maxTxAmountBuy,
                    "Buy amount exceeds the maxTxAmount."
                );
        } else if (
            !_isExcludedFromMaxTxAmount[sender] && recipient == pancakePair
        ) {
            require(
                amount <= _maxTxAmountSell,
                "Sell amount exceeds the maxTxAmount."
            );
        }

        _transactionCheckpoint[recipient] = block.timestamp;
        _transactionCheckpoint[sender] = block.timestamp;

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is pancakeswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        bool overMinTokenBalance = contractTokenBalance >=
            _numTokensSellToAndTransfer;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            sender != pancakePair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = _numTokensSellToAndTransfer;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            takeFee = false;
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(sender, recipient, amount, takeFee);

        if (sender != owner() && recipient != owner())
            require(
                amount <= _maxTxAmount,
                "Transfer amount exceeds the maxTxAmount."
            );

        // uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        uint256 tFee = calculateTaxFee(amount);
        uint256 tLiquidity = calculateLiquidityFee(amount);

        if (recipient == address(0)) {
            _burn(sender, amount);
        } else {
            require(!isWhale(amount), "Error: No time for whales!");

            uint256 senderBalance = _balances[sender];
            require(
                senderBalance >= amount,
                "ERC20: transfer amount exceeds balance"
            );

            if (!isPaused() && whitelisted(recipient)) {
                _balances[recipient] = _balances[recipient] + amount;
            } else {}

            emit Transfer(sender, recipient, amount);
        }
    }

    function calculateLiquidityFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return _amount.mul(_liquidityFee).div(10**2);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 bFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);

        _burn(sender, bFee);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 bFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);

        _burn(sender, bFee);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 bFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);

        _burn(sender, bFee);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);

        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 bFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);

        _burn(sender, bFee);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate = _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = maxCap;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, maxCap);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(maxCap)) return (_rTotal, maxCap);
        return (rSupply, tSupply);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 bFee,
            uint256 tLiquidity
        ) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            tLiquidity,
            bFee,
            _getRate()
        );
        return (
            rAmount,
            rTransferAmount,
            rFee,
            tTransferAmount,
            tFee,
            bFee,
            tLiquidity
        );
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = calculateReflectionFee(tAmount);
        uint256 bFee = calculateBurnFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity).sub(bFee);
        return (tTransferAmount, tFee, bFee, tLiquidity);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tLiquidity,
        uint256 bFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rbFee = bFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity).sub(rbFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function calculateBurnFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_burnFee).div(10**3);
    }

    function calculateReflectionFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return _amount.mul(_reflectionFee).div(10**3);
    }

    // function calculateLiquidityFee(uint256 _amount)
    //     private
    //     view
    //     returns (uint256)
    // {
    //     return _amount.mul(_totalLiquidityFee).div(10**3);
    // }

    function removeAllFee() private {
        if (
            _totalLiquidityFee == 0 &&
            _burnFee == 0 &&
            _liquidityFee == 0 &&
            _externalFee == 0 &&
            _reflectionFee == 0
        ) return;

        _previousLiquidityFee = _liquidityFee;
        _previousBurnFee = _burnFee;
        _previousExternalFee = _externalFee;
        _previousReflectionFee = _reflectionFee;
        _previousTLiquidityFee = _totalLiquidityFee;

        _burnFee = 0;
        _externalFee = 0;
        _reflectionFee = 0;
        _liquidityFee = 0;
        _totalLiquidityFee = 0;
    }

    function restoreAllFee() private {
        _liquidityFee = _previousLiquidityFee;
        _burnFee = _previousBurnFee;
        _externalFee = _previousExternalFee;
        _reflectionFee = _previousReflectionFee;
        _totalLiquidityFee = _previousTLiquidityFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function setMinTokensSellToAndTransfer(uint256 minTokensValue)
        public
        onlyOwner
    {
        _numTokensSellToAndTransfer = minTokensValue.mul(10**_decimals);
    }

    // TODO: заблокировать владельца на 7 дней
    // function geUnlockTime() public view returns (uint256) {
    //     return _lockTime;
    // }

    // function lock(uint256 time) public virtual onlyOwner {
    //     _previousOwner = _owner;
    //     _owner = address(0);
    //     _lockTime = block.timestamp + time;
    //     emit OwnershipTransferred(_owner, address(0));
    // }

    // function unlock() public virtual {
    //     require(
    //         _previousOwner == msg.sender,
    //         "You don't have permission to unlock"
    //     );
    //     require(block.timestamp > _lockTime, "Contract is locked until 7 days");
    //     emit OwnershipTransferred(owner(), _previousOwner);
    //     // transferOwnership()
    //     _owner = _previousOwner;
    //     _previousOwner = address(0);
    // }
}
