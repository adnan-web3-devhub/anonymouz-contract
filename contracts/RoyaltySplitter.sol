// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RoyaltySplitter - Distribution for ETH and ERC20 (push + pull)
/// @notice Immutable recipients and shares. Mint revenue is PUSHED straight to recipient
///         wallets via {distributeERC20Push}; ETH and other ERC20 royalties use the
///         pull-based credit/{withdrawERC20} path.
/// @dev Distributes BOTH mint revenue (routed in by LumanaNFT) and secondary royalties
///      (paid directly by marketplaces) across recipients by the same shares. ERC20 amounts
///      are based on measured on-chain receipts, never a caller-supplied amount.
///      DEFAULT_ADMIN_ROLE uses two-step delayed transfer
///      ({AccessControlDefaultAdminRules}); set it to a multisig after deployment.
contract RoyaltySplitter is AccessControlDefaultAdminRules, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Delay enforced on the two-step DEFAULT_ADMIN_ROLE transfer.
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    address[] public recipients;
    uint256[] public shares;
    uint256 public totalShares;

    mapping(address => uint256) public pendingETH;
    mapping(address => mapping(IERC20 => uint256)) public pendingERC20;

    /// @notice Total ERC20 credited to recipients but not yet withdrawn (per token).
    /// @dev Used to compute the un-accounted surplus that rescueERC20 may sweep.
    mapping(IERC20 => uint256) public totalPendingERC20;

    // Events
    event RoyaltyReceived(address indexed token, uint256 amount);
    event Withdrawn(
        address indexed recipient,
        address indexed token,
        uint256 amount
    );
    event Rescued(address indexed token, address indexed to, uint256 amount);

    // Custom errors
    error InvalidRecipients();
    error InvalidShares();
    error NoPendingBalance();
    error TransferFailed();
    error NoSurplus();
    error ZeroAddress();
    error NothingToDistribute();

    /// @param _recipients Array of recipient addresses
    /// @param _shares Array of shares (basis points, e.g., 5000 = 50%)
    constructor(
        address[] memory _recipients,
        uint256[] memory _shares
    ) AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, msg.sender) {
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
        // DEFAULT_ADMIN_ROLE is granted to msg.sender by AccessControlDefaultAdminRules.
    }

    /// @notice Receive ETH royalties
    receive() external payable {
        _distributeETH(msg.value);
        emit RoyaltyReceived(address(0), msg.value);
    }

    /// @notice Credit newly-arrived ERC20 funds (mint revenue or secondary royalties)
    ///         across recipients by shares.
    /// @dev Trustless and permissionless: distributes only the MEASURED balance that has
    ///      arrived since the last accounting (balanceOf - totalPendingERC20). No
    ///      caller-supplied amount can be forged, so an attacker cannot over-credit.
    ///      Integer-division dust stays as un-accounted surplus recoverable via rescueERC20.
    /// @param token ERC20 token to distribute
    function distributeERC20(IERC20 token) external {
        uint256 pull = token.balanceOf(address(this)) - totalPendingERC20[token];
        if (pull == 0) revert NothingToDistribute();

        uint256 distributed = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 share = (pull * shares[i]) / totalShares;
            pendingERC20[recipients[i]][token] += share;
            distributed += share;
        }
        totalPendingERC20[token] += distributed;

        emit RoyaltyReceived(address(token), pull);
    }

    /// @notice Immediately PUSH newly-arrived ERC20 funds to each recipient's wallet by share.
    /// @dev Like {distributeERC20} but transfers tokens out instead of crediting pending
    ///      balances. Distributes only the MEASURED, un-accounted balance
    ///      (balanceOf - totalPendingERC20), so it never touches funds already credited via
    ///      the pull path. Integer-division dust is sent to the last recipient so the
    ///      newly-arrived amount is drained completely (nothing left in the splitter).
    ///      `nonReentrant`; uses {SafeERC20}. NOTE: a recipient that cannot receive the token
    ///      (e.g. token-level freeze/blocklist) would make this revert — keep recipients as
    ///      plain payout addresses. The pull-based {distributeERC20}/{withdrawERC20} remain
    ///      available as a fallback.
    /// @param token ERC20 token to distribute
    function distributeERC20Push(IERC20 token) external nonReentrant {
        uint256 amount = token.balanceOf(address(this)) - totalPendingERC20[token];
        if (amount == 0) revert NothingToDistribute();

        uint256 n = recipients.length;
        uint256 distributed = 0;
        for (uint256 i = 0; i < n; i++) {
            uint256 share;
            if (i == n - 1) {
                share = amount - distributed; // remainder + dust to last recipient
            } else {
                share = (amount * shares[i]) / totalShares;
                distributed += share;
            }
            token.safeTransfer(recipients[i], share);
            emit Withdrawn(recipients[i], address(token), share);
        }

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
        totalPendingERC20[token] -= amount;
        token.safeTransfer(msg.sender, amount);
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
                totalPendingERC20[tokens[i]] -= amount;
                tokens[i].safeTransfer(msg.sender, amount);
                emit Withdrawn(msg.sender, address(tokens[i]), amount);
            }
        }
    }

    /// @notice Sweep ERC20 surplus sent directly to the splitter (not via distributeERC20).
    /// @dev Admin-gated. Can only move tokens beyond what recipients are owed
    ///      (balance - totalPendingERC20), so accounted royalties are never touched.
    /// @param token ERC20 token to rescue
    /// @param to Recipient of the swept surplus
    function rescueERC20(
        IERC20 token,
        address to
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = token.balanceOf(address(this));
        uint256 accounted = totalPendingERC20[token];
        if (balance <= accounted) revert NoSurplus();
        uint256 surplus = balance - accounted;
        token.safeTransfer(to, surplus);
        emit Rescued(address(token), to, surplus);
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
}
