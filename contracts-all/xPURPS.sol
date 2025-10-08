// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract xPURPS is ERC20, ERC20Permit, ERC20Burnable {
    uint256 constant MAX_SUPPLY = 100_000_000 * 10 ** 18;

    constructor() ERC20("xPurps", "xPURPS") ERC20Permit("xPurps") {
        _mint(msg.sender, MAX_SUPPLY);
    }
}
