import { ethers } from "hardhat";

async function main() {
  const nftAddress = process.env.NFT_ADDRESS || "0xYourNFTAddress";
  const updaterAddress = process.env.UPDATER_ADDRESS || "0xYourUpdaterAddress"; // Chainlink keeper
  const LumanaNFT = await ethers.getContractAt("LumanaNFT", nftAddress);

  const STATE_UPDATER_ROLE = await LumanaNFT.STATE_UPDATER_ROLE();
  const tx = await LumanaNFT.grantRole(STATE_UPDATER_ROLE, updaterAddress);
  await tx.wait();
  console.log(`Granted STATE_UPDATER_ROLE to ${updaterAddress}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
