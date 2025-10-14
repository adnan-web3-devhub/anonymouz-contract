import { ethers } from "hardhat";

async function main() {
  const nftAddress = process.env.NFT_ADDRESS || "0xYourNFTAddress"; // Set after deploy
  const LumanaNFT = await ethers.getContractAt("LumanaNFT", nftAddress);

  // Example URIs (replace with Arweave hashes)
  const uris = [
    "https://arweave.net/state0/",
    "https://arweave.net/state1/",
    "https://arweave.net/state2/",
    "https://arweave.net/state3/",
    "https://arweave.net/state4/",
    "https://arweave.net/state5/",
    "https://arweave.net/state6/"
  ];

  for (let i = 0; i <= 6; i++) {
    const tx = await LumanaNFT.setBaseURI(i, uris[i]);
    await tx.wait();
    console.log(`Set URI for state ${i}: ${uris[i]}`);
  }

  console.log("Base URIs set!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
