/**
 * Sepolia deployment + Etherscan verification (no Hardhat runtime).
 *
 *   npx tsx scripts/deploySepolia.ts
 *
 * Requires: SEPOLIA_RPC_URL, SEPOLIA_PRIVATE_KEY, ETHERSCAN_API_KEY
 *           ROYALTY_RECIPIENT_1/2/3
 */
import * as dotenv from "dotenv";
dotenv.config();

import { readFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { ethers } from "ethers";

const NAME = "THA LUMANA'I";
const SYMBOL = "LUMANA";
const TIER = 1;
const PRICE = 6200n;
const USDT_DECIMALS = 6;

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v || v.startsWith("0x...") || v === "") {
    throw new Error(`Missing env: ${name}`);
  }
  return v;
}

function loadArtifact(name: string) {
  const path = `out/${name}.sol/${name}.json`;
  const raw = JSON.parse(readFileSync(path, "utf8"));
  return { abi: raw.abi, bytecode: raw.bytecode.object as string };
}

function forgeVerify(
  contractPath: string,
  address: string,
  constructorArgs: string
) {
  if (process.env.SKIP_VERIFY === "true") return;
  const forge =
    process.env.FORGE_BIN ??
    `${process.env.USERPROFILE ?? process.env.HOME}/foundry-bin/forge.exe`;
  const apiKey = requireEnv("ETHERSCAN_API_KEY");
  const rpc = requireEnv("SEPOLIA_RPC_URL");
  console.log(`  Verifying ${address}...`);
  try {
    execSync(
      `"${forge}" verify-contract ${address} ${contractPath} ` +
        `--constructor-args ${constructorArgs} ` +
        `--rpc-url "${rpc}" --etherscan-api-key "${apiKey}" --chain sepolia --watch`,
      { stdio: "inherit" }
    );
    console.log(`  ✅ Verified ${address}`);
  } catch {
    console.error(`  ⚠️  Verify failed for ${address}`);
  }
}

async function main() {
  const rpc = requireEnv("SEPOLIA_RPC_URL");
  const pk = requireEnv("SEPOLIA_PRIVATE_KEY");
  const provider = new ethers.JsonRpcProvider(rpc);
  const deployer = new ethers.Wallet(pk, provider);

  const recipients = [
    requireEnv("ROYALTY_RECIPIENT_1"),
    requireEnv("ROYALTY_RECIPIENT_2"),
    requireEnv("ROYALTY_RECIPIENT_3"),
  ];
  const shares = [3333n, 3333n, 3334n];

  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance:  ${ethers.formatEther(await provider.getBalance(deployer.address))} ETH`);

  const MockUSDT = loadArtifact("MockUSDT");
  const RoyaltySplitter = loadArtifact("RoyaltySplitter");
  const LumanaNFT = loadArtifact("LumanaNFT");

  console.log("\n1. MockUSDT...");
  const usdtFactory = new ethers.ContractFactory(
    MockUSDT.abi,
    MockUSDT.bytecode,
    deployer
  );
  const usdt = await usdtFactory.deploy(USDT_DECIMALS);
  await usdt.waitForDeployment();
  const usdtAddress = await usdt.getAddress();
  console.log(`   ${usdtAddress}`);

  console.log("\n2. RoyaltySplitter...");
  const splitterFactory = new ethers.ContractFactory(
    RoyaltySplitter.abi,
    RoyaltySplitter.bytecode,
    deployer
  );
  const splitter = await splitterFactory.deploy(recipients, shares);
  await splitter.waitForDeployment();
  const splitterAddress = await splitter.getAddress();
  console.log(`   ${splitterAddress}`);

  console.log("\n3. LumanaNFT...");
  const nftFactory = new ethers.ContractFactory(
    LumanaNFT.abi,
    LumanaNFT.bytecode,
    deployer
  );
  const nft = await nftFactory.deploy(
    NAME,
    SYMBOL,
    TIER,
    usdtAddress,
    USDT_DECIMALS,
    PRICE,
    splitterAddress
  );
  await nft.waitForDeployment();
  const nftAddress = await nft.getAddress();
  console.log(`   ${nftAddress}`);

  console.log("\n--- Summary ---");
  console.log(`MockUSDT:        ${usdtAddress}`);
  console.log(`RoyaltySplitter: ${splitterAddress}`);
  console.log(`LumanaNFT:       ${nftAddress}`);

  const coder = ethers.AbiCoder.defaultAbiCoder();
  console.log("\n4. Etherscan verification...");
  forgeVerify(
    "contracts/MockUSDT.sol:MockUSDT",
    usdtAddress,
    coder.encode(["uint8"], [USDT_DECIMALS])
  );
  forgeVerify(
    "contracts/RoyaltySplitter.sol:RoyaltySplitter",
    splitterAddress,
    coder.encode(["address[]", "uint256[]"], [recipients, shares])
  );
  forgeVerify(
    "contracts/LumanaNFT.sol:LumanaNFT",
    nftAddress,
    coder.encode(
      [
        "string",
        "string",
        "uint8",
        "address",
        "uint8",
        "uint256",
        "address",
      ],
      [NAME, SYMBOL, TIER, usdtAddress, USDT_DECIMALS, PRICE, splitterAddress]
    )
  );

  console.log("\nUpdate .env:");
  console.log(`USDT_ADDRESS="${usdtAddress}"`);
  console.log(`SPLITTER_ADDRESS="${splitterAddress}"`);
  console.log(`NFT_ADDRESS="${nftAddress}"`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
