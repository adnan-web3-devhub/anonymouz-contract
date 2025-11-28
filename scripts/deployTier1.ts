// @ts-ignore - Hardhat Runtime Environment
import { ethers } from "hardhat";

async function main() {
    console.log("Deploying LumanaNFT Tier 1 (Ethereum Mainnet)...");

    // Configuration
    const NAME = "4 THA LUMANA'I - Tier 1";
    const SYMBOL = "LUMANA1";
    const PRICE = 6200; // $6,200 USDT
    const USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // Ethereum USDT
    const ROYALTY_SPLITTER = "0x..."; // Deploy RoyaltySplitter first!

    if (ROYALTY_SPLITTER === "0x...") {
        throw new Error("❌ Set ROYALTY_SPLITTER address first!");
    }

    // Deploy
    const LumanaNFT = await ethers.getContractFactory("LumanaNFT");
    const nft = await LumanaNFT.deploy(
        NAME,
        SYMBOL,
        USDT_ADDRESS,
        PRICE,
        ROYALTY_SPLITTER
    );
    await nft.waitForDeployment();

    const address = await nft.getAddress();
    console.log(`✅ Tier 1 NFT deployed to: ${address}`);

    // Display configuration
    console.log("\nConfiguration:");
    console.log(`  Name: ${NAME}`);
    console.log(`  Symbol: ${SYMBOL}`);
    console.log(`  Price: $${PRICE.toLocaleString()} USDT`);
    console.log(`  Max Supply: 62 NFTs`);
    console.log(`  Network: Ethereum Mainnet`);
    console.log(`  Royalty: 5% to ${ROYALTY_SPLITTER}`);

    console.log("\n📋 Next Steps:");
    console.log("  1. Set base URIs for states 0-6: setBaseURI(state, uri)");
    console.log("  2. Set launch time: setLaunchTime(timestamp)");
    console.log("  3. Grant STATE_UPDATER_ROLE to Chainlink Automation");
    console.log("  4. Transfer DEFAULT_ADMIN_ROLE to multi-sig wallet");
    console.log("  5. Register Chainlink Automation upkeep");

    console.log(`\n⚠️  Save this address: ${address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
