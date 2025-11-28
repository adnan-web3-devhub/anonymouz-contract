// @ts-ignore - Hardhat Runtime Environment
import { ethers } from "hardhat";

async function main() {
  console.log("Deploying RoyaltySplitter...");

  // Configuration
  const recipients = [
    "0x...", // Artist address
    "0x...", // Cast member 1
    "0x...", // Cast member 2
    "0x...", // Cultural DAO treasury
  ];

  const shares = [
    4000, // 40% to artist
    3000, // 30% to cast member 1
    2000, // 20% to cast member 2
    1000, // 10% to Cultural DAO
  ]; // Must sum to 10000 (100%)

  // Validate configuration
  const totalShares = shares.reduce((a, b) => a + b, 0);
  if (totalShares !== 10000) {
    throw new Error(`Total shares must equal 10000, got ${totalShares}`);
  }

  if (recipients.length !== shares.length) {
    throw new Error("Recipients and shares arrays must have same length");
  }

  // Deploy
  const RoyaltySplitter = await ethers.getContractFactory("RoyaltySplitter");
  const splitter = await RoyaltySplitter.deploy(recipients, shares);
  await splitter.waitForDeployment();

  const address = await splitter.getAddress();
  console.log(`✅ RoyaltySplitter deployed to: ${address}`);

  // Verify configuration
  console.log("\nConfiguration:");
  for (let i = 0; i < recipients.length; i++) {
    console.log(`  ${recipients[i]}: ${shares[i] / 100}%`);
  }

  console.log("\n⚠️  IMPORTANT: Save this address for NFT contract deployment!");
  console.log(`   RoyaltySplitter: ${address}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
