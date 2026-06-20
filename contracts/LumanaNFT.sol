// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Minimal view of the RoyaltySplitter used to split transferred funds in-tx.
interface IRoyaltySplitter {
    function distributeERC20Push(IERC20 token) external;
}

/// @title LumanaNFT - Dynamic NFT for "4 THA LUMANA'I"
/// @notice ERC-721 with USDT minting, date-driven metadata states, and royalty support.
/// @dev One tier per deployment. The same bytecode is deployed once per chain, each
///      carrying a single immutable tier and a single per-chain price/USDT config.
/// @dev DEFAULT_ADMIN_ROLE uses {AccessControlDefaultAdminRules} (single holder, two-step
///      delayed transfer). The initial admin is the deployer; transfer it to a multisig
///      via beginDefaultAdminTransfer/acceptDefaultAdminTransfer after deployment.
contract LumanaNFT is
    ERC721,
    AccessControlDefaultAdminRules,
    ReentrancyGuard,
    Pausable,
    ERC2981,
    IERC4906
{
    using SafeERC20 for IERC20;

    bytes32 public constant STATE_UPDATER_ROLE =
        keccak256("STATE_UPDATER_ROLE");

    /// @notice Delay enforced on the two-step DEFAULT_ADMIN_ROLE transfer.
    uint48 public constant ADMIN_TRANSFER_DELAY = 3 days;

    /// @notice Per-chain mint cap (token IDs 1..62).
    uint256 public constant MAX_SUPPLY = 62;

    /// @notice Fixed metadata-evolution thresholds (UTC unix timestamps).
    /// @dev NZ daylight-saving offset already accounted for in these constants.
    uint256 public constant CHRISTMAS_TS = 1798132800; // 2026-12-25 06:20 NZT
    uint256 public constant INDEPENDENCE_TS = 1811830800; // 2027-06-01 18:20 NZT

    /// @notice Tier carried by this deployment (1=AUMAGA, 2=TULAFALE, 3=ALI'I).
    uint8 public immutable TIER;

    /// @notice Decimals of the USDT contract on this chain (e.g. 6 on ETH/Polygon, 18 on BSC).
    uint8 public immutable usdtDecimals;

    // State variables
    address public usdtAddress;
    uint256 public supply;
    uint256 public price; // USDT price in whole units (e.g. 6200 for 6200 USDT)
    address public royaltySplitter; // EIP-2981 receiver AND mint-revenue distributor
    mapping(uint8 => string) public baseURIByState; // states 1, 2, 3 only

    // Events
    event Minted(address indexed to, uint256 quantity, uint256 totalMinted);
    event URIRootUpdated(uint8 state, string uri);
    event Withdrawn(address indexed to, uint256 amount);

    // Custom errors
    error SoldOut();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidState();
    error InvalidTier();
    error InvalidQuantity();
    error TransferFailed();
    error ZeroAddress();
    error InvalidPrice();
    error InvalidDecimals();
    error NothingToWithdraw();

    /// @param _name NFT name
    /// @param _symbol NFT symbol
    /// @param _tier Tier carried by this deployment (must be 1, 2, or 3)
    /// @param _usdtAddress USDT contract address on this chain
    /// @param _usdtDecimals Decimals of the USDT contract on this chain
    /// @param _price Price in whole USDT units (e.g. 6200 for 6200 USDT)
    /// @param _royaltySplitter Address of the royalty splitter (EIP-2981 receiver and
    ///        mint-revenue distributor)
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _tier,
        address _usdtAddress,
        uint8 _usdtDecimals,
        uint256 _price,
        address _royaltySplitter
    )
        ERC721(_name, _symbol)
        AccessControlDefaultAdminRules(ADMIN_TRANSFER_DELAY, msg.sender)
    {
        if (_tier < 1 || _tier > 3) revert InvalidTier();
        if (_usdtAddress == address(0)) revert ZeroAddress();
        if (_royaltySplitter == address(0)) revert ZeroAddress();
        if (_price == 0) revert InvalidPrice();
        if (_usdtDecimals > 18) revert InvalidDecimals();

        // DEFAULT_ADMIN_ROLE is granted to msg.sender by AccessControlDefaultAdminRules.
        _grantRole(STATE_UPDATER_ROLE, msg.sender); // transfer to cron wallet post-deploy

        TIER = _tier;
        usdtAddress = _usdtAddress;
        usdtDecimals = _usdtDecimals;
        price = _price;
        royaltySplitter = _royaltySplitter;
        _setDefaultRoyalty(_royaltySplitter, 500); // 5% royalty
    }

    /// @notice Human-readable name for this deployment's tier.
    function tierName() public view returns (string memory) {
        if (TIER == 1) return "AUMAGA";
        if (TIER == 2) return "TULAFALE";
        return "ALI'I";
    }

    /// @notice Mint NFTs with USDT payment.
    /// @dev Payment is sent straight to the royalty splitter, which immediately PUSHES each
    ///      recipient's share to their wallet in the same transaction (no withdraw step, no
    ///      pending balances). No USDT is ever held by this contract or left in the splitter.
    ///      This function is `nonReentrant` and the splitter's push is also guarded.
    /// @param quantity Number of NFTs to mint
    function mintWithUSDT(
        uint256 quantity
    ) external nonReentrant whenNotPaused {
        if (quantity == 0) revert InvalidQuantity();
        if (supply + quantity > MAX_SUPPLY) revert SoldOut();

        uint256 totalPrice = price * quantity * (10 ** usdtDecimals);
        IERC20 usdt = IERC20(usdtAddress);

        if (usdt.allowance(msg.sender, address(this)) < totalPrice)
            revert InsufficientAllowance();
        if (usdt.balanceOf(msg.sender) < totalPrice)
            revert InsufficientBalance();

        // Forward payment to the splitter, then push each recipient's share to their wallet.
        usdt.safeTransferFrom(msg.sender, royaltySplitter, totalPrice);

        uint256 startTokenId = _nextTokenId();
        for (uint256 i = 0; i < quantity; i++) {
            _mint(msg.sender, startTokenId + i);
        }

        supply += quantity;
        IRoyaltySplitter(royaltySplitter).distributeERC20Push(usdt);
        emit Minted(msg.sender, quantity, supply);
    }

    /// @notice Current metadata state derived LIVE from block.timestamp.
    /// @return 1 before Christmas, 2 between Christmas and Independence, 3 after Independence.
    function currentState() public view returns (uint8) {
        if (block.timestamp < CHRISTMAS_TS) return 1;
        if (block.timestamp < INDEPENDENCE_TS) return 2;
        return 3;
    }

    /// @notice Emit a metadata-refresh event for the whole collection.
    /// @dev Minimal-privilege hook for an off-chain cron, called right after each
    ///      evolution timestamp. No timing checks, no state mutation, no ownership effects.
    function triggerMetadataRefresh() external onlyRole(STATE_UPDATER_ROLE) {
        emit BatchMetadataUpdate(1, MAX_SUPPLY); // ERC-4906
    }

    /// @notice Get all token IDs owned by an address
    /// @param owner Address to query
    /// @return uint256[] Array of token IDs owned by the address
    function getOwnerTokens(
        address owner
    ) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        if (tokenCount == 0) return new uint256[](0);

        uint256[] memory tokens = new uint256[](tokenCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= supply && index < tokenCount; i++) {
            if (_ownerOf(i) == owner) {
                tokens[index] = i;
                index++;
            }
        }

        return tokens;
    }

    /// @notice Set base URI for a state (only DEFAULT_ADMIN_ROLE)
    /// @param state The state (1, 2, or 3)
    /// @param uri The base URI for that state (public placeholder metadata only)
    function setBaseURI(
        uint8 state,
        string memory uri
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (state < 1 || state > 3) revert InvalidState();
        baseURIByState[state] = uri;
        emit URIRootUpdated(state, uri);
    }

    /// @notice Get token URI based on the live current state.
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory base = baseURIByState[currentState()];
        if (bytes(base).length == 0) return "";
        return string.concat(base, _toString(tokenId));
    }

    /// @notice Emergency pause minting (only DEFAULT_ADMIN_ROLE)
    function emergencyPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Emergency unpause minting (only DEFAULT_ADMIN_ROLE)
    function emergencyUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Pause minting (only DEFAULT_ADMIN_ROLE)
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause minting (only DEFAULT_ADMIN_ROLE)
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Safety sweep: route any stray USDT held by this contract to the royalty
    ///         splitter, which pushes it to recipients by share in the same transaction.
    /// @dev Normal mints forward payment to the splitter directly, so this contract should
    ///      hold no USDT. This remains as a recovery path for USDT sent here by mistake.
    ///      Routes the full balance to `royaltySplitter`, then calls its
    ///      `distributeERC20Push` so funds land in recipient wallets immediately.
    ///      `nonReentrant`, and the splitter's push is also guarded.
    function withdrawUSDT() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        IERC20 usdt = IERC20(usdtAddress);
        uint256 balance = usdt.balanceOf(address(this));
        if (balance == 0) revert NothingToWithdraw();
        usdt.safeTransfer(royaltySplitter, balance);
        IRoyaltySplitter(royaltySplitter).distributeERC20Push(usdt);
        emit Withdrawn(royaltySplitter, balance);
    }

    /// @notice Supports ERC-721, ERC-2981, ERC-4906
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, AccessControlDefaultAdminRules, ERC2981, IERC165)
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC4906).interfaceId;
    }

    /// @dev Internal function to get next token ID
    function _nextTokenId() internal view returns (uint256) {
        return _ownerOf(1) == address(0) ? 1 : totalSupply() + 1;
    }

    /// @dev Total supply (ERC721 doesn't have this by default)
    function totalSupply() public view returns (uint256) {
        return supply;
    }

    /// @dev Convert uint256 to string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
