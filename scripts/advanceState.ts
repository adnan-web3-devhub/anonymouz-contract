import { ethers } from "hardhat";

async function main() {
  const nftAddress = process.env.NFT_ADDRESS || "0xYourNFTAddress";
  const LumanaNFT = await ethers.getContractAt("LumanaNFT", nftAddress);

  const currentState = await LumanaNFT.currentState();
  console.log(`Current state: ${currentState}`);

  if (currentState >= 6) {
    console.log("Already at max state!");
    return;
  }

  const tx = await LumanaNFT.advanceState();
  await tx.wait();
  console.log(`Advanced to state ${await LumanaNFT.currentState()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
