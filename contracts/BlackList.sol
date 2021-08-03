// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BlackList is Ownable {
    mapping(address => bool) private _isBlacklisted;

    function blacklistSingleWallet(address addresses) public onlyOwner {
        if (_isBlacklisted[addresses] == true) return;
        _isBlacklisted[addresses] = true;
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
            _isBlacklisted[addresses[i]] = true;
        }
    }

    function isBlacklisted(address addresses) public view returns (bool) {
        return _isBlacklisted[addresses];
    }

    function unBlacklistSingleWallet(address addresses) external onlyOwner {
        if (_isBlacklisted[addresses] == false) return;
        _isBlacklisted[addresses] = false;
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
            _isBlacklisted[addresses[i]] = false;
        }
    }
}
