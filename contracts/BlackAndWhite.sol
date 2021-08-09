// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "./AntiWhale.sol";

// После эмиссии % идет на Whitelist, потом (какое-то событие) участники листа могут забрать себе 20%,
// и так каждый месяц, пока не исчерпается фонд Вайтлиста
contract BlackAndWhite is AntiWhale, Pausable {
    bool wlPaused;

    mapping(address => bool) private _isWhiteListed;
    mapping(address => bool) private _isBlackListed;

    //         require(!_isBlacklisted[sender], "You are banned");
    // require(!_isBlacklisted[recipient], "The recipient is banned");

    event Whitelisted(address indexed account, bool isWhitelisted);

    function whitelisted(address _address) public view returns (bool) {
        if (paused()) {
            return true;
        }

        return _isWhiteListed[_address];
    }

    function addAddress(address _address) public onlyOwner {
        require(_isWhiteListed[_address] != true);

        if (!paused()) {
            _isWhiteListed[_address] = true;
            emit Whitelisted(_address, true);
        }
    }

    function removeAddress(address _address) public onlyOwner {
        require(_isWhiteListed[_address] != false);
        _isWhiteListed[_address] = false;
        emit Whitelisted(_address, false);
    }

    function isPaused() public view returns (bool) {
        return wlPaused;
    }

    function blacklistSingleWallet(address addresses) public onlyOwner {
        if (_isBlackListed[addresses] == true) return;
        _isBlackListed[addresses] = true;
    }

    function blacklistMultipleWallets(address[] calldata addresses)
        public
        onlyOwner
    {
        require(
            addresses.length <= 800,
            "Can only blacklist 800 addresses per transaction"
        );
        for (uint256 i; i < addresses.length; ++i) {
            _isBlackListed[addresses[i]] = true;
        }
    }

    function isBlacklisted(address addresses) public view returns (bool) {
        return _isBlackListed[addresses];
    }

    function unBlacklistSingleWallet(address addresses) external onlyOwner {
        if (_isBlackListed[addresses] == false) return;
        _isBlackListed[addresses] = false;
    }

    function unBlacklistMultipleWallets(address[] calldata addresses)
        public
        onlyOwner
    {
        require(
            addresses.length <= 800,
            "Can only unblacklist 800 addresses per transaction"
        );
        for (uint256 i; i < addresses.length; ++i) {
            _isBlackListed[addresses[i]] = false;
        }
    }
}
