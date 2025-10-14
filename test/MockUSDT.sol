// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDT - ERC20 mock for testing USDT minting
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000 * 10**decimals()); // 1M USDT
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
