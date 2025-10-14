import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Config (adjust as needed)
  const usdtAddress = process.env.USDT_ADDRESS || "0xYourUSDTAddress"; // Replace with actual USDT
  const tierPrices = [1000000, 2000000, 3000000]; // 1, 2, 3 USDT (6 decimals)
  const recipients = ["0xRecipient1", "0xRecipient2"]; // Replace with actual addresses
  const shares = [5000, 5000]; // 50% each
  const totalRoyaltyBps = 500; // 5%

  // Deploy RoyaltySplitter
  const RoyaltySplitter = await ethers.getContractFactory("RoyaltySplitter");
  const splitter = await RoyaltySplitter.deploy(recipients, shares, totalRoyaltyBps);
  await splitter.waitForDeployment();
  console.log("RoyaltySplitter deployed to:", await splitter.getAddress());

  // Deploy LumanaNFT
  const LumanaNFT = await ethers.getContractFactory("LumanaNFT");
  const nft = await LumanaNFT.deploy(
    "LumanaNFT",
    "LUM",
    usdtAddress,
    tierPrices,
    await splitter.getAddress()
  );
  await nft.waitForDeployment();
  console.log("LumanaNFT deployed to:", await nft.getAddress());

  // Grant roles (optional, for testing)
  const STATE_UPDATER_ROLE = await nft.STATE_UPDATER_ROLE();
  await nft.grantRole(STATE_UPDATER_ROLE, deployer.address);
  console.log("Granted STATE_UPDATER_ROLE to deployer");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
