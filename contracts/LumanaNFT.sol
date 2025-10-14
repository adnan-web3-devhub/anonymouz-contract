// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LumanaNFT - Dynamic NFT for "4 THA LUMANA’I" Film
/// @notice ERC-721 with tiered USDT minting, global state evolutions, and royalty support
contract LumanaNFT is ERC721, AccessControl, ReentrancyGuard, Pausable, ERC2981, IERC4906 {
    bytes32 public constant STATE_UPDATER_ROLE = keccak256("STATE_UPDATER_ROLE");

    enum Tier { TIER1, TIER2, TIER3 }

    uint8 public constant MAX_STATE = 6;
    uint256 public constant MAX_SUPPLY_PER_TIER = 62;
    uint256 public constant TOTAL_SUPPLY = 186; // 3 * 62

    // State variables
    uint8 public currentState;
    address public usdtAddress;
    mapping(Tier => uint256) public tierSupply;
    mapping(Tier => uint256) public tierPrices; // USDT prices per tier
    mapping(uint8 => string) public baseURIByState;
    address public royaltySplitter;

    // Events
    event Minted(address indexed to, Tier tier, uint256 quantity, uint256 totalMinted);
    event StateAdvanced(uint8 oldState, uint8 newState, uint256 timestamp);
    event URIRootUpdated(uint8 state, string uri);

    // Custom errors
    error InvalidTier();
    error SoldOut();
    error InsufficientAllowance();
    error InsufficientBalance();
    error InvalidState();
    error Unauthorized();
    error InvalidQuantity();
    error TransferFailed();

    /// @param _name NFT name
    /// @param _symbol NFT symbol
    /// @param _usdtAddress USDT contract address
    /// @param _tierPrices Array of prices for TIER1, TIER2, TIER3 in USDT (6 decimals)
    /// @param _royaltySplitter Address of the royalty splitter
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdtAddress,
        uint256[3] memory _tierPrices,
        address _royaltySplitter
    ) ERC721(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        usdtAddress = _usdtAddress;
        tierPrices[Tier.TIER1] = _tierPrices[0];
        tierPrices[Tier.TIER2] = _tierPrices[1];
        tierPrices[Tier.TIER3] = _tierPrices[2];
        royaltySplitter = _royaltySplitter;
        _setDefaultRoyalty(_royaltySplitter, 500); // 5% royalty
    }

    /// @notice Mint NFTs with USDT payment
    /// @param tier The tier to mint (0=TIER1, 1=TIER2, 2=TIER3)
    /// @param quantity Number of NFTs to mint
    function mintWithUSDT(Tier tier, uint256 quantity) external nonReentrant whenNotPaused {
        if (tier > Tier.TIER3) revert InvalidTier();
        if (quantity == 0) revert InvalidQuantity();
        if (tierSupply[tier] + quantity > MAX_SUPPLY_PER_TIER) revert SoldOut();

        uint256 totalPrice = tierPrices[tier] * quantity;
        IERC20 usdt = IERC20(usdtAddress);

        if (usdt.allowance(msg.sender, address(this)) < totalPrice) revert InsufficientAllowance();
        if (usdt.balanceOf(msg.sender) < totalPrice) revert InsufficientBalance();

        bool success = usdt.transferFrom(msg.sender, address(this), totalPrice);
        if (!success) revert TransferFailed();

        uint256 startTokenId = _nextTokenId();
        for (uint256 i = 0; i < quantity; i++) {
            _mint(msg.sender, startTokenId + i);
        }

        tierSupply[tier] += quantity;
        emit Minted(msg.sender, tier, quantity, tierSupply[tier]);
    }

    /// @notice Get current global state (0-6)
    function getCurrentState() external view returns (uint8) {
        return currentState;
    }

    /// @notice Advance to next state (only STATE_UPDATER_ROLE)
    function advanceState() external onlyRole(STATE_UPDATER_ROLE) {
        if (currentState >= MAX_STATE) revert InvalidState();
        uint8 oldState = currentState;
        currentState++;
        emit StateAdvanced(oldState, currentState, block.timestamp);
        emit BatchMetadataUpdate(1, TOTAL_SUPPLY); // ERC-4906
    }

    /// @notice Set base URI for a state (only DEFAULT_ADMIN_ROLE)
    /// @param state The state (0-6)
    /// @param uri The base URI for that state
    function setBaseURI(uint8 state, string memory uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (state > MAX_STATE) revert InvalidState();
        baseURIByState[state] = uri;
        emit URIRootUpdated(state, uri);
    }

    /// @notice Get token URI based on current state
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory base = baseURIByState[currentState];
        return bytes(base).length > 0 ? string(abi.encodePacked(base, _toString(tokenId))) : "";
    }

    /// @notice Pause minting (pre-launch only, DEFAULT_ADMIN_ROLE)
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause minting (pre-launch only, DEFAULT_ADMIN_ROLE)
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Withdraw collected USDT to royalty splitter
    function withdrawUSDT() external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20 usdt = IERC20(usdtAddress);
        uint256 balance = usdt.balanceOf(address(this));
        if (balance > 0) {
            bool success = usdt.transfer(royaltySplitter, balance);
            if (!success) revert TransferFailed();
        }
    }

    /// @notice Supports ERC-721, ERC-2981, ERC-4906
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl, ERC2981, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IERC4906).interfaceId;
    }

    /// @dev Internal function to get next token ID
    function _nextTokenId() internal view returns (uint256) {
        return _ownerOf(1) == address(0) ? 1 : totalSupply() + 1;
    }

    /// @dev Total supply (ERC721 doesn't have this by default)
    function totalSupply() public view returns (uint256) {
        uint256 supply = 0;
        for (uint256 i = 1; i <= TOTAL_SUPPLY; i++) {
            if (_ownerOf(i) != address(0)) supply++;
        }
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
