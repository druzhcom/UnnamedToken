// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./AntiWhale.sol";

// После эмиссии % идет на Whitelist, потом(какое-то событие) участники листа могут забрать себе 20%, и так каждый месяц, пока не исчерпается фонд Вайтлиста
contract WhiteList is AntiWhale, Pausable {
    bool wlPaused;

    mapping(address => bool) private whitelistedMap;

    event Whitelisted(address indexed account, bool isWhitelisted);

    function whitelisted(address _address) public view returns (bool) {
        if (paused()) {
            return true;
        }

        return whitelistedMap[_address];
    }

    function addAddress(address _address) public onlyOwner {
        require(whitelistedMap[_address] != true);

        if (!paused()) {
            whitelistedMap[_address] = true;
            emit Whitelisted(_address, true);
        }
    }

    function removeAddress(address _address) public onlyOwner {
        require(whitelistedMap[_address] != false);
        whitelistedMap[_address] = false;
        emit Whitelisted(_address, false);
    }

    function isPaused() public view returns (bool) {
        return wlPaused;
    }
}
