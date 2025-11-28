# "4 THA LUMANA’I" Dynamic NFT Film Smart Contracts

Production-grade smart contracts for the "4 THA LUMANA’I" film project, featuring dynamic ERC-721 NFTs with tiered USDT minting, global state evolutions, and royalty management.

## Architecture Overview

### Core Contracts

#### LumanaNFT.sol
- **ERC-721** with dynamic metadata via ERC-4906
- **Tiered Minting**: 3 tiers (Tier1: $6,200, Tier2: $620, Tier3: $62 USDT), 62 NFTs per tier (186 total)
- **State Evolution**: 7 global states (0-6), advanced by Chainlink Automation
- **Royalty Support**: EIP-2981 with pull-based distribution
- **Access Control**: Multi-sig admin, STATE_UPDATER role for Chainlink
- **Pausable**: Emergency pause functionality
- **Chainlink Automation**: Automatic time-based state progression
- **Lit Protocol**: NFT-gated content access support

#### RoyaltySplitter.sol
- **Pull-based Royalties**: Recipients withdraw their share manually
- **Immutable Recipients**: Fixed shares set at deployment
- **Multi-token Support**: ETH and ERC20 royalties
- **Proportional Distribution**: Shares allocated by basis points (10000 = 100%)
- **Batch Withdrawal**: Gas-efficient multi-token withdrawal
- **Fixed Bug**: Removed double royalty deduction

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
   npm install --legacy-peer-deps
   ```

2. **Compile Contracts**
   ```bash
   forge build  # or npm run build
   ```

3. **Deploy RoyaltySplitter** (Ethereum)
   ```bash
   npx hardhat run scripts/deployRoyaltySplitter.ts --network mainnet
   ```

4. **Deploy Tier 1 NFT** (Ethereum)
   ```bash
   npx hardhat run scripts/deployTier1.ts --network mainnet
   ```

5. **Deploy Tier 2 & 3 NFTs** (Polygon)
   ```bash
   npx hardhat run scripts/deployTier2.ts --network polygon
   npx hardhat run scripts/deployTier3.ts --network polygon
   ```

6. **Set Launch Time** (all tiers - same timestamp)
   ```bash
   npx hardhat run scripts/setLaunchTime.ts --network mainnet
   npx hardhat run scripts/setLaunchTime.ts --network polygon
   ```

7. **Configure Chainlink Automation**
   ```bash
   NFT_ADDRESS=<tier1> CHAINLINK_FORWARDER=<address> \
     npx hardhat run scripts/configureChainlinkAutomation.ts --network mainnet
   
   # Repeat for Tier 2 & 3 on Polygon
   ```

8. **Set Base URIs**
   ```bash
   npx hardhat run scripts/setBaseURIs.ts --network mainnet
   npx hardhat run scripts/setBaseURIs.ts --network polygon
   ```

9. **Transfer Ownership**
   ```bash
   npx hardhat run scripts/transferOwnership.ts --network mainnet
   npx hardhat run scripts/transferOwnership.ts --network polygon
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
2. Call `mintWithUSDT(quantity)`
3. Contract validates supply, balance, allowance
4. Transfers USDT, mints NFTs, emits events

### State Evolution
- States advance from 0 to 6 automatically via Chainlink Automation
- Each advance triggers ERC-4906 metadata update
- View functions: `getCurrentState()`, `getNextRevealTime()`, `getTimeUntilNextState()`

### Chainlink Automation
- Registers upkeep for each tier contract
- Calls `performUpkeep()` when time elapsed
- Triggers state advancement automatically
- No manual intervention required

### Lit Protocol Integration
- Use `isEligibleForContent(user, requiredState)` to check access
- Returns true if user owns NFT and current state >= required state
- Integrate with Lit Actions for decryption key release
- Example flow:
  ```typescript
  const eligible = await nft.isEligibleForContent(userAddress, 1);
  if (eligible) {
    // Request decryption key from Lit Protocol
    const key = await litProtocol.getDecryptionKey({...});
    // Decrypt and play video
  }
  ```

### Royalty Distribution
- Royalties accumulate in RoyaltySplitter
- Recipients call `withdrawETH()` or `withdrawERC20(token)`
- Use `withdrawBatch(tokens[])` for gas efficiency
- Check balances: `getAllPending(recipient, tokens[])`

### Metadata Updates
- Listen for `BatchMetadataUpdate` events
- Refresh metadata for all tokens when state changes
- Base URI per state enables different artwork per evolution

### Helper Functions for dApp
```typescript
// Get all tokens owned by user
const tokens = await nft.getOwnerTokens(userAddress);

// Get next reveal countdown
const timeRemaining = await nft.getTimeUntilNextState();
const nextTimestamp = await nft.getNextRevealTime();

// Check current state
const currentState = await nft.currentState();
```

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
