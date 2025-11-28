// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title RoyaltySplitter - Pull-based royalty distribution for ETH and ERC20
/// @notice Immutable recipients and shares, supports ETH and ERC20 withdrawals
contract RoyaltySplitter is AccessControl, ReentrancyGuard {
    address[] public recipients;
    uint256[] public shares;
    uint256 public totalShares;

    mapping(address => uint256) public pendingETH;
    mapping(address => mapping(IERC20 => uint256)) public pendingERC20;

    // Events
    event RoyaltyReceived(address indexed token, uint256 amount);
    event Withdrawn(
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    // Custom errors
    error InvalidRecipients();
    error InvalidShares();
    error NoPendingBalance();
    error TransferFailed();

    /// @param _recipients Array of recipient addresses
    /// @param _shares Array of shares (basis points, e.g., 5000 = 50%)
    constructor(address[] memory _recipients, uint256[] memory _shares) {
        if (_recipients.length != _shares.length || _recipients.length == 0)
            revert InvalidRecipients();
        uint256 total = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            if (_shares[i] == 0) revert InvalidShares();
            total += _shares[i];
        }
        if (total != 10000) revert InvalidShares(); // Must sum to 10000 bps

        recipients = _recipients;
        shares = _shares;
        totalShares = total;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Receive ETH royalties
    receive() external payable {
        _distributeETH(msg.value);
        emit RoyaltyReceived(address(0), msg.value);
    }

    /// @notice Distribute ERC20 royalties (called by NFT contract on transfer)
    /// @param token ERC20 token address
    /// @param amount Amount received
    function distributeERC20(IERC20 token, uint256 amount) external {
        _distributeERC20(token, amount);
        emit RoyaltyReceived(address(token), amount);
    }

    /// @notice Withdraw pending ETH
    function withdrawETH() external nonReentrant {
        uint256 amount = pendingETH[msg.sender];
        if (amount == 0) revert NoPendingBalance();
        pendingETH[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(msg.sender, address(0), amount);
    }

    /// @notice Withdraw pending ERC20
    /// @param token ERC20 token address
    function withdrawERC20(IERC20 token) external nonReentrant {
        uint256 amount = pendingERC20[msg.sender][token];
        if (amount == 0) revert NoPendingBalance();
        pendingERC20[msg.sender][token] = 0;
        bool success = token.transfer(msg.sender, amount);
        if (!success) revert TransferFailed();
        emit Withdrawn(msg.sender, address(token), amount);
    }

    /// @notice Get pending ETH for a recipient
    function getPendingETH(address recipient) external view returns (uint256) {
        return pendingETH[recipient];
    }

    /// @notice Get pending ERC20 for a recipient
    function getPendingERC20(
        address recipient,
        IERC20 token
    ) external view returns (uint256) {
        return pendingERC20[recipient][token];
    }

    /// @notice Get all pending balances for a recipient
    /// @param recipient Address to check
    /// @param tokens Array of ERC20 tokens to check
    function getAllPending(
        address recipient,
        IERC20[] calldata tokens
    )
        external
        view
        returns (uint256 ethPending, uint256[] memory tokenPending)
    {
        ethPending = pendingETH[recipient];
        tokenPending = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            tokenPending[i] = pendingERC20[recipient][tokens[i]];
        }
    }

    /// @notice Withdraw both ETH and multiple ERC20 tokens in one transaction
    /// @param tokens Array of ERC20 tokens to withdraw
    function withdrawBatch(IERC20[] calldata tokens) external nonReentrant {
        // Withdraw ETH
        uint256 ethAmount = pendingETH[msg.sender];
        if (ethAmount > 0) {
            pendingETH[msg.sender] = 0;
            (bool success, ) = msg.sender.call{value: ethAmount}("");
            if (!success) revert TransferFailed();
            emit Withdrawn(msg.sender, address(0), ethAmount);
        }

        // Withdraw all tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = pendingERC20[msg.sender][tokens[i]];
            if (amount > 0) {
                pendingERC20[msg.sender][tokens[i]] = 0;
                bool success = tokens[i].transfer(msg.sender, amount);
                if (!success) revert TransferFailed();
                emit Withdrawn(msg.sender, address(tokens[i]), amount);
            }
        }
    }

    /// @dev Distribute ETH proportionally
    /// @notice Marketplaces send only the royalty amount (via EIP-2981), so we distribute 100% of received amount
    /// Example: 10 ETH sale with 5% royalty → marketplace sends 0.5 ETH → we distribute full 0.5 ETH to recipients
    function _distributeETH(uint256 amount) internal {
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share = (amount * shares[i]) / totalShares;
            pendingETH[recipients[i]] += share;
        }
    }

    /// @dev Distribute ERC20 proportionally
    /// @notice Marketplaces send only the royalty amount (via EIP-2981), so we distribute 100% of received amount
    /// Example: 10 WETH sale with 5% royalty → marketplace sends 0.5 WETH → we distribute full 0.5 WETH to recipients
    function _distributeERC20(IERC20 token, uint256 amount) internal {
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share = (amount * shares[i]) / totalShares;
            pendingERC20[recipients[i]][token] += share;
        }
    }
}
