// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title NonCompliantUSDT
/// @notice Mimics Ethereum-mainnet Tether USD: transfer/transferFrom/approve return NO data
///         (they are NOT declared to return bool), exactly like 0xdAC17F958...ec7.
/// @dev Deliberately does NOT inherit IERC20 — a bool-checked call against this token would
///      revert on return-data decoding. Used to prove SafeERC20 handles it correctly.
contract NonCompliantUSDT {
    string public name = "Tether USD";
    string public symbol = "USDT";
    uint8 private immutable _decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
        _mint(msg.sender, 1_000_000 * 10 ** decimals_);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    // --- Intentionally NO return value (ETH-USDT style) ---

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 bal = balanceOf[from];
        require(bal >= amount, "balance");
        unchecked {
            balanceOf[from] = bal - amount;
        }
        balanceOf[to] += amount;
    }
}
