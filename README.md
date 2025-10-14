# "4 THA LUMANA’I" Dynamic NFT Film Smart Contracts

Production-grade smart contracts for the "4 THA LUMANA’I" film project, featuring dynamic ERC-721 NFTs with tiered USDT minting, global state evolutions, and royalty management.

## Architecture Overview

### Core Contracts

#### LumanaNFT.sol
- **ERC-721** with dynamic metadata via ERC-4906
- **Tiered Minting**: 3 tiers (TIER1: 1M USDT, TIER2: 2M USDT, TIER3: 3M USDT), 62 NFTs per tier (186 total)
- **State Evolution**: 7 global states (0-6), advanced by automation
- **Royalty Support**: EIP-2981 with pull-based distribution
- **Access Control**: Multi-sig admin, STATE_UPDATER role for state management
- **Pausable**: Emergency pause functionality

#### RoyaltySplitter.sol
- **Pull-based Royalties**: Recipients withdraw their share manually
- **Immutable Recipients**: Fixed shares set at deployment
- **Multi-token Support**: ETH and ERC20 royalties
- **Proportional Distribution**: Shares allocated by basis points (500 = 5%)

### Security Features
- **ReentrancyGuard**: Prevents reentrancy attacks
- **Pausable**: Emergency stop mechanism
- **AccessControl**: Role-based permissions
- **Input Validation**: Comprehensive error handling
- **Safe Transfers**: ERC20 transfer checks

## Deployment Runbook

### Prerequisites
- Node.js 18+ (avoid 23.x due to Hardhat compatibility)
- Foundry (via foundryup)
- USDT contract address on target network

### Environment Variables
```bash
SEPOLIA_RPC_URL=your_sepolia_rpc_url
SEPOLIA_PRIVATE_KEY=your_private_key
MAINNET_RPC_URL=your_mainnet_rpc_url
MAINNET_PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key
```

### Deployment Steps

1. **Install Dependencies**
   ```bash
   npm install
   ```

2. **Compile Contracts**
   ```bash
   forge build
   ```

3. **Run Tests**
   ```bash
   forge test
   ```

4. **Deploy to Testnet**
   ```bash
   npx hardhat run scripts/deploy.ts --network sepolia
   ```

5. **Set Base URIs**
   ```bash
   npx hardhat run scripts/setBaseURIs.ts --network sepolia
   ```

6. **Grant Roles**
   ```bash
   npx hardhat run scripts/grantRoles.ts --network sepolia
   ```

7. **Transfer Ownership**
   ```bash
   npx hardhat run scripts/transferOwnership.ts --network sepolia
   ```

### Post-Deployment Configuration

- **Set Base URIs**: Configure IPFS/Arweave URIs for each state
- **Grant STATE_UPDATER Role**: Assign to automation service
- **Transfer Admin Role**: Move to multi-sig wallet
- **Verify Contracts**: Use Etherscan verification

## Threat Model

### Attack Vectors Considered

#### 1. Reentrancy
- **Mitigation**: ReentrancyGuard on all external functions
- **Coverage**: All minting and withdrawal functions protected

#### 2. Access Control Bypass
- **Mitigation**: OpenZeppelin AccessControl with role-based permissions
- **Coverage**: Admin-only functions, state updater restrictions

#### 3. Integer Overflow/Underflow
- **Mitigation**: Solidity 0.8.28 built-in overflow checks
- **Coverage**: All arithmetic operations safe

#### 4. Front-running
- **Mitigation**: No time-sensitive operations, fair minting process
- **Coverage**: Minting order doesn't affect functionality

#### 5. Denial of Service
- **Mitigation**: Gas-efficient loops, bounded operations
- **Coverage**: Total supply limits prevent infinite loops

#### 6. Oracle Manipulation
- **Mitigation**: No external price feeds used
- **Coverage**: Fixed USDT prices, no dependency on oracles

### Trust Assumptions
- **USDT Contract**: Assumes standard ERC20 implementation
- **Multi-sig Admin**: Trusted for emergency functions
- **State Updater**: Trusted automation service for state advances

## dApp Integration Notes

### Minting Flow
1. User approves USDT spending
2. Call `mintWithUSDT(tier, quantity)`
3. Contract validates supply, balance, allowance
4. Transfers USDT, mints NFTs, emits events

### State Evolution
- States advance from 0 to 6 automatically
- Each advance triggers ERC-4906 metadata update
- Off-chain services monitor and update metadata

### Royalty Distribution
- Royalties accumulate in RoyaltySplitter
- Recipients call `withdrawETH()` or `withdrawERC20(token)`
- Proportional to configured shares

### Metadata Updates
- Listen for `BatchMetadataUpdate` events
- Refresh metadata for all tokens when state changes
- Base URI per state enables different artwork per evolution

## Testing & Coverage

### Test Suites
- **Foundry Tests**: 6 LumanaNFT tests, all passing
- **Coverage**: 56.20% lines, 54.78% statements, 25.00% branches, 53.33% functions

### Gas Usage (Foundry Snapshot)
- Mint single NFT: ~145k gas
- Advance state: ~23k gas
- Total supply invariant test: ~5.2M gas (186 NFTs)

### Key Test Scenarios
- Tiered minting with USDT payment
- Supply limits and overflow protection
- State advancement and bounds checking
- Royalty distribution and withdrawal
- Access control and role management

## Development

### Setup
```bash
npm install
forge install
```

### Testing
```bash
forge test                    # Run all tests
forge test --match-contract LumanaNFTTest  # Run specific suite
forge coverage               # Generate coverage report
forge snapshot               # Gas usage snapshot
```

### Scripts
```bash
npx hardhat run scripts/deploy.ts --network localhost  # Local deployment
npx hardhat run scripts/advanceState.ts --network localhost  # Dry-run state advance
```

## Contract Addresses

### Sepolia Testnet
- LumanaNFT: [TBD]
- RoyaltySplitter: [TBD]
- USDT: 0x036CbD53842c5426634e7929541eC2318f3dCF7e (Mock)

### Mainnet
- LumanaNFT: [TBD]
- RoyaltySplitter: [TBD]
- USDT: 0xdAC17F958D2ee523a2206206994597C13D831ec7 (Tether)

## Contributing

1. Follow Solidity style guide
2. Add tests for new functionality
3. Update documentation
4. Run full test suite before PR

## License

MIT
