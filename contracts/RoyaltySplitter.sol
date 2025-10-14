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
    uint256 public totalRoyaltyBps; // e.g., 500 for 5%

    mapping(address => uint256) public pendingETH;
    mapping(address => mapping(IERC20 => uint256)) public pendingERC20;

    // Events
    event RoyaltyReceived(address indexed token, uint256 amount);
    event Withdrawn(address indexed recipient, address indexed token, uint256 amount);

    // Custom errors
    error InvalidRecipients();
    error InvalidShares();
    error NoPendingBalance();
    error TransferFailed();

    /// @param _recipients Array of recipient addresses
    /// @param _shares Array of shares (basis points, e.g., 5000 = 50%)
    /// @param _totalRoyaltyBps Total royalty in basis points (e.g., 500 = 5%)
    constructor(address[] memory _recipients, uint256[] memory _shares, uint256 _totalRoyaltyBps) {
        if (_recipients.length != _shares.length || _recipients.length == 0) revert InvalidRecipients();
        uint256 total = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            if (_shares[i] == 0) revert InvalidShares();
            total += _shares[i];
        }
        if (total != 10000) revert InvalidShares(); // Must sum to 10000 bps

        recipients = _recipients;
        shares = _shares;
        totalShares = total;
        totalRoyaltyBps = _totalRoyaltyBps;
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
        (bool success,) = msg.sender.call{value: amount}("");
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
    function getPendingERC20(address recipient, IERC20 token) external view returns (uint256) {
        return pendingERC20[recipient][token];
    }

    /// @dev Distribute ETH proportionally
    function _distributeETH(uint256 amount) internal {
        uint256 royaltyAmount = (amount * totalRoyaltyBps) / 10000;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share = (royaltyAmount * shares[i]) / totalShares;
            pendingETH[recipients[i]] += share;
        }
    }

    /// @dev Distribute ERC20 proportionally
    function _distributeERC20(IERC20 token, uint256 amount) internal {
        uint256 royaltyAmount = (amount * totalRoyaltyBps) / 10000;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share = (royaltyAmount * shares[i]) / totalShares;
            pendingERC20[recipients[i]][token] += share;
        }
    }
}
