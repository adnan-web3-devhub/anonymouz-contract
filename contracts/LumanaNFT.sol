// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/interfaces/IERC4906.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title LumanaNFT - Dynamic NFT for "4 THA LUMANA’I" Film
/// @notice ERC-721 with tiered USDT minting, global state evolutions, and royalty support
contract LumanaNFT is ERC721, AccessControl, ReentrancyGuard, Pausable, ERC2981, IERC4906 {
    bytes32 public constant STATE_UPDATER_ROLE = keccak256("STATE_UPDATER_ROLE");

    uint8 public constant MAX_STATE = 6;
    uint256 public constant MAX_SUPPLY = 62;

    // State variables
    uint8 public currentState;
    address public usdtAddress;
    uint256 public supply;
    uint256 public price; // USDT price (whole units, adjusted for decimals)
    uint8 public decimals; // Decimals from USDT contract
    uint256 public launchTime;
    uint256[6] public intervals; // Time intervals for each state advancement
    mapping(uint8 => string) public baseURIByState;
    address public royaltySplitter;

    // Events
    event Minted(address indexed to, uint256 quantity, uint256 totalMinted);
    event StateAdvanced(uint8 oldState, uint8 newState, uint256 timestamp);
    event URIRootUpdated(uint8 state, string uri);

    // Custom errors
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
    /// @param _price Price in whole USDT units (e.g., 6200 for 6200 USDT)
    /// @param _royaltySplitter Address of the royalty splitter
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdtAddress,
        uint256 _price,
        address _royaltySplitter
    ) ERC721(_name, _symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        usdtAddress = _usdtAddress;
        price = _price;
        decimals = IERC20Metadata(usdtAddress).decimals();
        // Set intervals: 62 minutes, 62 hours, 62 days, 62 weeks, 62 months (approx 30 days), 62 years (approx 365 days)
        intervals[0] = 62 * 60; // minutes
        intervals[1] = 62 * 3600; // hours
        intervals[2] = 62 * 86400; // days
        intervals[3] = 62 * 604800; // weeks
        intervals[4] = 62 * 2592000; // months (30 days)
        intervals[5] = 62 * 31536000; // years (365 days)
        currentState = 0; // Explicitly set to 0
        royaltySplitter = _royaltySplitter;
        _setDefaultRoyalty(_royaltySplitter, 500); // 5% royalty
    }

    /// @notice Mint NFTs with USDT payment
    /// @param quantity Number of NFTs to mint
    function mintWithUSDT(uint256 quantity) external nonReentrant whenNotPaused {
        if (quantity == 0) revert InvalidQuantity();
        if (supply + quantity > MAX_SUPPLY) revert SoldOut();

        uint256 totalPrice = price * quantity * (10 ** decimals);
        IERC20 usdt = IERC20(usdtAddress);

        if (usdt.allowance(msg.sender, address(this)) < totalPrice) revert InsufficientAllowance();
        if (usdt.balanceOf(msg.sender) < totalPrice) revert InsufficientBalance();

        bool success = usdt.transferFrom(msg.sender, address(this), totalPrice);
        if (!success) revert TransferFailed();

        uint256 startTokenId = _nextTokenId();
        for (uint256 i = 0; i < quantity; i++) {
            _mint(msg.sender, startTokenId + i);
        }

        supply += quantity;
        emit Minted(msg.sender, quantity, supply);
    }

    /// @notice Advance to next state (public, time-based)
    function advanceState() external {
        if (launchTime == 0) revert InvalidState(); // Launch time not set
        uint256 elapsed = block.timestamp - launchTime;
        uint8 current = currentState;
        uint256 cumulative = 0;
        for (uint8 i = 0; i < current; i++) {
            cumulative += intervals[i];
        }
        if (elapsed < cumulative) revert InvalidState(); // Not enough time passed
        if (current >= MAX_STATE) revert InvalidState();
        uint8 oldState = currentState;
        currentState = currentState + 1;
        emit StateAdvanced(oldState, currentState, block.timestamp);
        emit BatchMetadataUpdate(1, MAX_SUPPLY); // ERC-4906
    }

    /// @notice Get current global state (0-6)
    function getCurrentState() external view returns (uint8) {
        if (launchTime == 0) return currentState;
        uint256 elapsed = block.timestamp - launchTime;
        uint8 state = 0;
        uint256 cumulative = 0;
        for (uint8 i = 0; i < 6; i++) {
            cumulative += intervals[i];
            if (elapsed >= cumulative) {
                state = i + 1;
            } else {
                break;
            }
        }
        return state > MAX_STATE ? MAX_STATE : state;
    }

    /// @notice Set launch time (only DEFAULT_ADMIN_ROLE)
    /// @param _launchTime Timestamp when evolution starts
    function setLaunchTime(uint256 _launchTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        launchTime = _launchTime;
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
        uint8 state = currentState;
        if (launchTime != 0) {
            uint256 elapsed = block.timestamp - launchTime;
            uint256 cumulative = 0;
            for (uint8 i = 0; i < 6; i++) {
                cumulative += intervals[i];
                if (elapsed >= cumulative) {
                    state = i + 1;
                } else {
                    break;
                }
            }
            if (state > MAX_STATE) state = MAX_STATE;
        }
        string memory base = baseURIByState[state];
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
