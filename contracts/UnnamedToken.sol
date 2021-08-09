// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./FeeManagment.sol";

// import "./LiquidityManagment.sol";

// TODO: мультиподпись - несколько владельцев контракта - коллективное управление контракт
// TODO: добавить функцию с приватным списком адресов для эйрдропа и инфлюенсерам
// TODO: функция эйрдопа
// TODO: Токенсейл, если мы недошли до хардкепа, то снимает
// TODO: нужен смарт-контракт для Вайтлиста
// TODO: контракт для отсекания по адресам, по времени (в минуту 3 транзакции) + включаемая и отключаемая функция, примерно 3 транзакции в минуту

contract UnnamedToken is ERC20, FeeManagment {
    using SafeMath for uint256;
    // using Address for address;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => uint256) private _transactionCheckpoint; // время, когда адрес совершил предыдущую транзакцию
    mapping(address => bool) public _isExcludeFromExternalTokenMinAmount; // TODO WTF
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) private _isExcludedFromTransactionlock; // исключенные из списка адресов, которые имеют ограничения на отправку транзакций
    mapping(address => bool) private _isExcludedFromMaxTxAmount; // Ограничение на количество покупаемых токенов

    address[] private _excluded;

    uint8 private _decimals = 18;
    uint256 private _tFeeTotal;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    ERC20 public _externalToken; // OR IBEP

    bool inSwapAndLiquify;
    bool public isExternalTokenHoldEnabled;
    bool public swapAndLiquifyEnabled = true;

    uint256 private constant MAX = ~uint256(0);
    uint256 constant maxCap = 1000000000 * (10**18);
    uint256 private _rTotal = (MAX - (MAX % maxCap));
    uint256 public _maxTxAmount = 12500 * 10**6 * 10**9;
    uint256 private _lockTime;
    uint256 private _transactionLockTime = 0; // время через которое адрес может совершить новую транзакцию
    uint256 public _externalTokenMinAmount = 50000 * 10**6 * 10**_decimals;
    uint256 public _maxTxAmountBuy = 1000000 * 10**6 * 10**_decimals;
    uint256 public _maxTxAmountSell = 1000000 * 10**6 * 10**_decimals;
    uint256 public _numTokensSellToAndTransfer = 500000 * 10**6 * 10**_decimals;
    // Максимальное количество токенов, которое может хранить один адрес?

    // event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    // event SwapAndLiquifyEnabledUpdated(bool enabled);
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

    // Китобой
    modifier antiWhale(address recipient, uint256 amount) {
        require(
            _isExcludedFromAntiWhale[recipient] || isWhale(amount),
            "Max tokens limit for this account reached. Or try lower amount"
        );
        _;
    }

    // на ВЛ - 15 %
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, maxCap);

        // 1 этап - для попаданяи в вайт лист нуэнго удовлетворить условиям, из вайтлиста выбирается количество адресов. которые будут участвовать в Сейле
        // 1,5 этап - на фонд ейрдорпа кидается 5%
        // 2 этап - токен сеейл, по участникам ВайтЛиста?
        // 3 этап - после хардкапа -  распределение токенов (20% по ВайтЛисту)
        // 4 этап - на листинге 1% аэрдорпа распределятся из фонда Эйрдропа
        // На момент распределение токенов нужно отключить дефялционную модель (рапсред 5%)

        // Указываем на путейщик Uniswap
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );

        // Создаём на пару WETH к этому токену
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        // Отмена сбора комиссий для следующих адресов:
        {
            excludeFromFee(address(this)); // Адрес токена
        }

        // Отмена правил антибота для следующих адресов:
        {
            _isExcludedFromTransactionlock[owner()] = true; // владелец
            _isExcludedFromTransactionlock[address(this)] = true; // токен
            _isExcludedFromTransactionlock[_uniswapV2Pair] = true; // Uniswap пара Токен-WETH
            _isExcludedFromTransactionlock[address(_uniswapV2Router)] = true; // Uniswap путейщик
        }

        // TODO WTF
        {
            _isExcludeFromExternalTokenMinAmount[owner()] = true;
            _isExcludeFromExternalTokenMinAmount[address(this)] = true;
            _isExcludeFromExternalTokenMinAmount[_uniswapV2Pair] = true;
            _isExcludeFromExternalTokenMinAmount[
                address(_uniswapV2Router)
            ] = true;
        }

        // Снятие ограничений на покупку токенов для:
        {
            _isExcludedFromMaxTxAmount[owner()] = true; // владелец токена
            _isExcludedFromMaxTxAmount[address(this)] = true; // токен
            _isExcludedFromMaxTxAmount[_uniswapV2Pair] = true; // пары Токен-WЕТН
            _isExcludedFromMaxTxAmount[address(_uniswapV2Router)] = true; // Путейщик
        }

        // Исключение из китобоя для:
        excludeFromAntiWhale(
            address(this),
            _uniswapV2Pair,
            address(_uniswapV2Router)
        );

        _isExcluded[address(0)] = true;
    }

    // TODO: функции распределения Токенов участникам ВЛ согласно проценту их учасития (0,5 - 3 BNB)

    // нужно часть переводить другим - нужно чтобы это можно было отключить
    // часть сжигается(1,5%), часть уходит в ликвидность(2%), холдерам(1.5%)
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override antiWhale(recipient, amount) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        // добавить проверку адреса отправителя и получателя на вхождение в чёрные списки BlackAndWhite

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
        if (sender == uniswapV2Pair) {
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
            !_isExcludedFromMaxTxAmount[sender] && recipient == uniswapV2Pair
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
            sender != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = _numTokensSellToAndTransfer;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (isExcludedFromFee(sender) || isExcludedFromFee(recipient)) {
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

        // uint256 tFee = calculateTaxFee(amount);
        // uint256 tLiquidity = calculateLiquidityFee(amount);

        if (recipient == address(0)) {
            _burn(sender, amount);
        } else {
            require(!isWhale(amount), "Error: No time for whales!");

            uint256 senderBalance = balanceOf(sender);
            require(
                senderBalance >= amount,
                "ERC20: transfer amount exceeds balance"
            );

            if (!isPaused() && whitelisted(recipient)) {
                _transfer(sender, recipient, amount); // TODO проверить вызывается ли функция ЕРС20 или локальная функция
            } else {}

            emit Transfer(sender, recipient, amount);
        }
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
        _takeLiquidity(tLiquidity, _getRate());
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
        _takeLiquidity(tLiquidity, _getRate());
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
        _takeLiquidity(tLiquidity, _getRate());
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
        _takeLiquidity(tLiquidity, _getRate());
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
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

    //  function deliver(uint256 tAmount) public {
    //     address sender = _msgSender();
    //     require(
    //         !_isExcluded[sender],
    //         "Excluded addresses cannot call this function"
    //     );
    //     (uint256 rAmount, , , , , ) = _getValues(tAmount);
    //     _rOwned[sender] = _rOwned[sender].sub(rAmount);
    //     _rTotal = _rTotal.sub(rAmount);
    //     _tFeeTotal = _tFeeTotal.add(tAmount);
    // }

    // function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     require(tAmount <= _tTotal, "Amount must be less than supply");
    //     if (!deductTransferFee) {
    //         (uint256 rAmount, , , , , ) = _getValues(tAmount);
    //         return rAmount;
    //     } else {
    //         (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
    //         return rTransferAmount;
    //     }
    // }

    // function tokenFromReflection(uint256 rAmount)
    //     public
    //     view
    //     returns (uint256)
    // {
    //     require(
    //         rAmount <= _rTotal,
    //         "Amount must be less than total reflections"
    //     );
    //     uint256 currentRate = _getRate();
    //     return rAmount.div(currentRate);
    // }

    // function excludeFromReward(address account) public onlyOwner {
    //     require(!_isExcluded[account], "Account is already excluded");
    //     if (_rOwned[account] > 0) {
    //         _tOwned[account] = tokenFromReflection(_rOwned[account]);
    //     }
    //     _isExcluded[account] = true;
    //     _excluded.push(account);
    // }

    // function includeInReward(address account) external onlyOwner {
    //     require(_isExcluded[account], "Account is already excluded");
    //     for (uint256 i = 0; i < _excluded.length; i++) {
    //         if (_excluded[i] == account) {
    //             _excluded[i] = _excluded[_excluded.length - 1];
    //             _tOwned[account] = 0;
    //             _isExcluded[account] = false;
    //             _excluded.pop();
    //             break;
    //         }
    //     }
    // }

    //     function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
    //     _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**2);
    // }

    // function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
    //     swapAndLiquifyEnabled = _enabled;
    //     emit SwapAndLiquifyEnabledUpdated(_enabled);
    // }

    function _reflectFee(uint256 rFee, uint256 tFee) internal {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    /// Функции взаимодействия с Uniswap
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal {
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

    function swapTokensForEth(uint256 tokenAmount) internal {
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

    function swapAndLiquify(uint256 contractTokenBalance) internal lockTheSwap {
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function _takeLiquidity(uint256 tLiquidity, uint256 curRate) internal {
        uint256 currentRate = curRate; // _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    receive() external payable {}
}
