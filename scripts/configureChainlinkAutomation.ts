// @ts-ignore - Hardhat Runtime Environment
import { ethers } from "hardhat";

/**
 * Grant STATE_UPDATER_ROLE to Chainlink Automation
 * This allows Chainlink to call advanceState() automatically
 */

async function main() {
    const NFT_ADDRESS = process.env.NFT_ADDRESS || "0x...";
    const CHAINLINK_FORWARDER = process.env.CHAINLINK_FORWARDER || "0x...";

    if (NFT_ADDRESS === "0x..." || CHAINLINK_FORWARDER === "0x...") {
        throw new Error("Set NFT_ADDRESS and CHAINLINK_FORWARDER environment variables");
    }

    console.log(`Granting STATE_UPDATER_ROLE to Chainlink Automation...`);
    console.log(`  NFT Contract: ${NFT_ADDRESS}`);
    console.log(`  Chainlink Forwarder: ${CHAINLINK_FORWARDER}`);

    const nft = await ethers.getContractAt("LumanaNFT", NFT_ADDRESS);
    const STATE_UPDATER_ROLE = await nft.STATE_UPDATER_ROLE();

    const tx = await nft.grantRole(STATE_UPDATER_ROLE, CHAINLINK_FORWARDER);
    await tx.wait();

    console.log(`✅ STATE_UPDATER_ROLE granted!`);
    console.log(`Transaction: ${tx.hash}`);

    // Verify
    const hasRole = await nft.hasRole(STATE_UPDATER_ROLE, CHAINLINK_FORWARDER);
    console.log(`\nVerification: ${hasRole ? "✅ Success" : "❌ Failed"}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
