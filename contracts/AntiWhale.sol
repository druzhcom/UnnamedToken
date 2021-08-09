// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AntiWhale is Ownable {
    uint256 public startDate;
    uint256 public endDate;
    uint256 public limitWhale;
    bool public antiWhaleActivated;

    mapping(address => bool) public _isExcludedFromAntiWhale;

    function excludeFromAntiWhale(
        address token,
        address uniswapV2Pair,
        address uniswapV2Router
    ) internal {
        _isExcludedFromAntiWhale[owner()] = true; // владельца токена
        _isExcludedFromAntiWhale[token] = true; // токена
        _isExcludedFromAntiWhale[uniswapV2Pair] = true; // пары Токен-ВЕТН
        _isExcludedFromAntiWhale[uniswapV2Router] = true; // путейщика
    }

    function activateAntiWhale() public onlyOwner {
        require(antiWhaleActivated == false);
        antiWhaleActivated = true;
    }

    function deActivateAntiWhale() public onlyOwner {
        require(antiWhaleActivated == true);
        antiWhaleActivated = false;
    }

    function setAntiWhale(
        uint256 _startDate,
        uint256 _endDate,
        uint256 _limitWhale
    ) public onlyOwner {
        startDate = _startDate;
        endDate = _endDate;
        limitWhale = _limitWhale;
        antiWhaleActivated = true;
    }

    function isWhale(uint256 amount) public view returns (bool) {
        if (
            msg.sender == owner() ||
            antiWhaleActivated == false ||
            amount <= limitWhale
        ) return false;

        if (block.timestamp >= startDate && block.timestamp <= endDate)
            return true;

        return false;
    }
}
