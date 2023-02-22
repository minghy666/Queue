//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";  

contract A3STest20Token is ERC20 {
    uint constant _initial_supply = 1000000 * (10**18);

    constructor() ERC20("A3STest20", "AST") {
        _mint(msg.sender, _initial_supply);
    }

    function mint(address to, uint256 amount) public{
        _mint(to, amount);
    }

    function decimals() public pure override returns(uint8){
        return 18;
    }

}