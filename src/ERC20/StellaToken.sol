// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Ownable is a contract that allows the owner to mint or burn tokens
contract StellaToken is ERC20, Ownable {
    
    /**
     * (1) the msg.sender is the owner of the contract
     * (2) the owner transfer ownership to multi-sig address
     * @param name token name
     * @param symbol token symbol
     * @param initialSupply initial supply of the token
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}