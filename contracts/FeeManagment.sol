// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./AntiWhale.sol";
import "./BlackAndWhite.sol";

contract FeeManagment is BlackAndWhite {
    using SafeMath for uint256;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;

    address[] private _excluded;

    uint8 private _decimals = 18;
    // uint256 private _tFeeTotal;
    uint256 public _taxFee = 5;
    uint256 public _liquidityFee = 5; // OR 60;

    uint256 private _lockTime;
    uint256 public _burnFee = 0;
    uint256 private _previousBurnFee = _burnFee;
    uint256 public _reflectionFee = 100;
    uint256 private _previousReflectionFee = _reflectionFee;
    uint256 public _externalFee = 90;
    uint256 private _previousExternalFee = _externalFee;
    uint256 private _previousLiquidityFee = _liquidityFee;
    uint256 private _totalLiquidityFee = _externalFee.add(_liquidityFee);
    uint256 private _previousTLiquidityFee = _totalLiquidityFee;

    constructor() {
        _isExcludedFromFee[owner()] = true; // исключить из вычета комиссии адрес владельца
    }

    function calculateTaxFee(uint256 _amount) internal view returns (uint256) {
        return _amount.mul(_taxFee).div(10**2);
    }

    function calculateLiquidityFee(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return _amount.mul(_liquidityFee).div(10**2);
        //     return _amount.mul(_totalLiquidityFee).div(10**3);
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner {
        _taxFee = taxFee;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    function calculateBurnFee(uint256 _amount) internal view returns (uint256) {
        return _amount.mul(_burnFee).div(10**3);
    }

    function calculateReflectionFee(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        return _amount.mul(_reflectionFee).div(10**3);
    }

    function removeAllFee() internal {
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

    function restoreAllFee() internal {
        _liquidityFee = _previousLiquidityFee;
        _burnFee = _previousBurnFee;
        _externalFee = _previousExternalFee;
        _reflectionFee = _previousReflectionFee;
        _totalLiquidityFee = _previousTLiquidityFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    // TODO: проверки
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }
}
