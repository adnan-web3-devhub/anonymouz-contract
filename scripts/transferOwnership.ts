import { ethers } from "hardhat";

async function main() {
  const nftAddress = process.env.NFT_ADDRESS || "0xYourNFTAddress";
  const splitterAddress = process.env.SPLITTER_ADDRESS || "0xYourSplitterAddress";
  const multiSig = process.env.MULTI_SIG || "0xYourMultiSigAddress";

  const LumanaNFT = await ethers.getContractAt("LumanaNFT", nftAddress);
  const RoyaltySplitter = await ethers.getContractAt("RoyaltySplitter", splitterAddress);

  // Transfer NFT admin to multi-sig
  const DEFAULT_ADMIN_ROLE = await LumanaNFT.DEFAULT_ADMIN_ROLE();
  await LumanaNFT.grantRole(DEFAULT_ADMIN_ROLE, multiSig);
  await LumanaNFT.renounceRole(DEFAULT_ADMIN_ROLE, (await ethers.getSigners())[0].address);
  console.log(`Transferred NFT admin to ${multiSig}`);

  // Transfer splitter admin to multi-sig
  await RoyaltySplitter.grantRole(DEFAULT_ADMIN_ROLE, multiSig);
  await RoyaltySplitter.renounceRole(DEFAULT_ADMIN_ROLE, (await ethers.getSigners())[0].address);
  console.log(`Transferred splitter admin to ${multiSig}`);

  // Withdraw any USDT to splitter
  await LumanaNFT.withdrawUSDT();
  console.log("Withdrew USDT to splitter");

  console.log("Ownership transferred and finalized!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
