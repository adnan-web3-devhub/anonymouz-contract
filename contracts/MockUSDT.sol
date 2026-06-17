// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDT - Testnet USDT stand-in (6 or 18 decimals, mintable)
contract MockUSDT is ERC20 {
    uint8 private immutable _decimals;

    constructor(uint8 decimals_) ERC20("Mock USDT", "USDT") {
        _decimals = decimals_;
        _mint(msg.sender, 1_000_000 * 10 ** decimals_); // 1M USDT to deployer
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
