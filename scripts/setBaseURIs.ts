import { ethers } from "hardhat";

/**
 * Set the base URI for each of the 3 metadata states (1, 2, 3).
 * URIs must point ONLY to public placeholder-image metadata — no film/video URL or CID.
 */
async function main() {
  const nftAddress = process.env.NFT_ADDRESS || "0xYourNFTAddress"; // Set after deploy
  const LumanaNFT = await ethers.getContractAt("LumanaNFT", nftAddress);

  // Replace with real public placeholder-metadata roots (e.g. Arweave/IPFS).
  const uris: Record<number, string> = {
    1: "https://arweave.net/state1/", // launch
    2: "https://arweave.net/state2/", // Christmas
    3: "https://arweave.net/state3/", // Independence
  };

  for (const state of [1, 2, 3]) {
    const tx = await LumanaNFT.setBaseURI(state, uris[state]);
    await tx.wait();
    console.log(`Set URI for state ${state}: ${uris[state]}`);
  }

  console.log("Base URIs set!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
