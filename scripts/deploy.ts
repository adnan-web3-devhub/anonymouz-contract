import { ethers } from "hardhat";

/**
 * Single parameterized deploy script. The SAME bytecode is deployed once per chain,
 * each carrying ONE tier + ONE price + ONE USDT config. The three deployments share
 * no state. Select the chain config with the CHAIN env var:
 *
 *   CHAIN=ethereum npx hardhat run scripts/deploy.ts --network mainnet
 *   CHAIN=bsc      npx hardhat run scripts/deploy.ts --network bsc
 *   CHAIN=polygon  npx hardhat run scripts/deploy.ts --network polygon
 *
 * Deploys RoyaltySplitter first, then LumanaNFT pointing at it.
 *
 * ⚠️  TODO BEFORE MAINNET: every address below is a placeholder. Fill in the real
 *     USDT token address and recipient list for each chain, and VERIFY each USDT
 *     address on that chain's block explorer before deploying. Do NOT trust these.
 */

const NAME = "4 THA LUMANA'I";
const SYMBOL = "LUMANA";

type ChainConfig = {
  tier: number; // 1 = AUMAGA, 2 = TULAFALE, 3 = ALI'I
  price: number; // whole USDT units (e.g. 6200)
  usdtDecimals: number; // USDT decimals on THIS chain
  usdtAddress: string; // TODO: verify on explorer
  recipients: string[]; // TODO: royalty + mint-revenue recipients
  shares: number[]; // basis points, must sum to 10000
};

// ⚠️ Placeholders only. Do not invent addresses — replace and verify before mainnet.
const TODO_USDT = "0x0000000000000000000000000000000000000000";
const TODO_RECIPIENT_A = "0x0000000000000000000000000000000000000000";
const TODO_RECIPIENT_B = "0x0000000000000000000000000000000000000000";

const CONFIGS: Record<string, ChainConfig> = {
  ethereum: {
    tier: 1, // AUMAGA
    price: 6200,
    usdtDecimals: 6, // Ethereum USDT = 6 decimals
    usdtAddress: TODO_USDT, // TODO: Ethereum USDT (verify, e.g. 0xdAC17F958D2ee523a2206206994597C13D831ec7)
    recipients: [TODO_RECIPIENT_A, TODO_RECIPIENT_B],
    shares: [5000, 5000],
  },
  bsc: {
    tier: 2, // TULAFALE
    price: 620,
    usdtDecimals: 18, // BSC USDT (BSC-USD) = 18 decimals
    usdtAddress: TODO_USDT, // TODO: BSC USDT (verify on bscscan)
    recipients: [TODO_RECIPIENT_A, TODO_RECIPIENT_B],
    shares: [5000, 5000],
  },
  polygon: {
    tier: 3, // ALI'I
    price: 62,
    usdtDecimals: 6, // Polygon USDT = 6 decimals
    usdtAddress: TODO_USDT, // TODO: Polygon USDT (verify on polygonscan)
    recipients: [TODO_RECIPIENT_A, TODO_RECIPIENT_B],
    shares: [5000, 5000],
  },
};

function loadConfig(): { key: string; cfg: ChainConfig } {
  const key = (process.env.CHAIN || "").toLowerCase();
  const cfg = CONFIGS[key];
  if (!cfg) {
    throw new Error(
      `Set CHAIN to one of: ${Object.keys(CONFIGS).join(", ")} (got "${process.env.CHAIN ?? ""}")`
    );
  }

  // Safety checks so a misconfigured deploy fails loudly instead of shipping placeholders.
  const total = cfg.shares.reduce((a, b) => a + b, 0);
  if (total !== 10000) throw new Error(`shares must sum to 10000, got ${total}`);
  if (cfg.recipients.length !== cfg.shares.length)
    throw new Error("recipients and shares length mismatch");
  if (cfg.usdtAddress === TODO_USDT)
    throw new Error(`❌ Fill in + verify the USDT address for "${key}" before deploying`);
  if (cfg.recipients.includes(TODO_RECIPIENT_A) || cfg.recipients.includes(TODO_RECIPIENT_B))
    throw new Error(`❌ Fill in real royalty recipients for "${key}" before deploying`);

  return { key, cfg };
}

async function main() {
  const { key, cfg } = loadConfig();
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying "${key}" (tier ${cfg.tier}) with account: ${deployer.address}`);

  // 1. RoyaltySplitter
  const RoyaltySplitter = await ethers.getContractFactory("RoyaltySplitter");
  const splitter = await RoyaltySplitter.deploy(cfg.recipients, cfg.shares);
  await splitter.waitForDeployment();
  const splitterAddress = await splitter.getAddress();
  console.log(`✅ RoyaltySplitter: ${splitterAddress}`);

  // 2. LumanaNFT
  const LumanaNFT = await ethers.getContractFactory("LumanaNFT");
  const nft = await LumanaNFT.deploy(
    NAME,
    SYMBOL,
    cfg.tier,
    cfg.usdtAddress,
    cfg.usdtDecimals,
    cfg.price,
    splitterAddress
  );
  await nft.waitForDeployment();
  const nftAddress = await nft.getAddress();
  console.log(`✅ LumanaNFT: ${nftAddress}`);

  console.log("\nConfiguration:");
  console.log(`  Chain:        ${key}`);
  console.log(`  Tier:         ${cfg.tier}`);
  console.log(`  Price:        ${cfg.price} USDT`);
  console.log(`  USDT decimals:${cfg.usdtDecimals}`);
  console.log(`  USDT address: ${cfg.usdtAddress}`);
  console.log(`  Splitter:     ${splitterAddress} (mint revenue + 5% royalty)`);

  console.log("\n📋 Next steps:");
  console.log("  1. setBaseURI(1|2|3, uri) for each metadata state (public placeholder only)");
  console.log("  2. grantRole(STATE_UPDATER_ROLE, cronWallet) for the metadata-refresh cron");
  console.log("  3. revoke STATE_UPDATER_ROLE from deployer once cron is set");
  console.log("  4. beginDefaultAdminTransfer(multisig); accept after the ADMIN_TRANSFER_DELAY");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
