// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./UnnamedToken.sol";

contract AirDrop is Ownable {
    UnnamedToken public tokenInstance;

    constructor(address _tokenAddress) {
        tokenInstance = UnnamedToken(_tokenAddress);
    }

    function doAirDrop(
        address payable[] memory _address,
        uint256 _amount,
        uint256 _ethAmount
    ) public onlyOwner returns (bool) {
        uint256 count = _address.length;
        for (uint256 i = 0; i < count; i++) {
            /* calling transfer function from contract */
            tokenInstance.transfer(_address[i], _amount);
            if (
                (_address[i].balance == 0) &&
                (address(this).balance >= _ethAmount)
            ) {
                require(_address[i].send(_ethAmount));
            }
        }
    }

    function sendBatch(address[] memory _recipients, uint256[] memory _values)
        public
        onlyOwner
        returns (bool)
    {
        require(_recipients.length == _values.length);
        for (uint256 i = 0; i < _values.length; i++) {
            tokenInstance.transfer(_recipients[i], _values[i]);
        }
        return true;
    }

    function transferEthToOnwer() public onlyOwner returns (bool res) {
        return payable(owner()).send(address(this).balance);
    }

    function kill() public onlyOwner {
        selfdestruct(payable(owner()));
    }
}
