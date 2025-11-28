// @ts-ignore - Hardhat Runtime Environment
import { ethers } from "hardhat";

/**
 * Configure all 3 tiers with launch time
 * This should be set to the same timestamp across all tiers
 * so they evolve in sync
 */

async function main() {
    // Configuration
    const TIER1_ADDRESS = "0x..."; // Ethereum
    const TIER2_ADDRESS = "0x..."; // Polygon
    const TIER3_ADDRESS = "0x..."; // Polygon

    // Set launch time (example: January 1, 2026 00:00:00 UTC)
    const LAUNCH_TIME = Math.floor(new Date("2026-01-01T00:00:00Z").getTime() / 1000);

    console.log(`Setting launch time to: ${new Date(LAUNCH_TIME * 1000).toISOString()}`);

    // Set for Tier 1 (Ethereum)
    if (TIER1_ADDRESS !== "0x...") {
        const tier1 = await ethers.getContractAt("LumanaNFT", TIER1_ADDRESS);
        const tx1 = await tier1.setLaunchTime(LAUNCH_TIME);
        await tx1.wait();
        console.log(`✅ Tier 1 launch time set`);
    }

    // For Tier 2 & 3, switch to Polygon network first
    console.log("\n⚠️  Switch to Polygon network to set Tier 2 & 3");
    console.log("Run: npx hardhat run scripts/setLaunchTime.ts --network polygon");

    /*
    const tier2 = await ethers.getContractAt("LumanaNFT", TIER2_ADDRESS);
    const tx2 = await tier2.setLaunchTime(LAUNCH_TIME);
    await tx2.wait();
    console.log(`✅ Tier 2 launch time set`);
  
    const tier3 = await ethers.getContractAt("LumanaNFT", TIER3_ADDRESS);
    const tx3 = await tier3.setLaunchTime(LAUNCH_TIME);
    await tx3.wait();
    console.log(`✅ Tier 3 launch time set`);
    */

    console.log("\n✅ Launch time configuration complete!");
    console.log("\nEvolution Schedule:");
    console.log(`  State 0 → 1: +62 minutes`);
    console.log(`  State 1 → 2: +62 hours`);
    console.log(`  State 2 → 3: +62 days`);
    console.log(`  State 3 → 4: +62 weeks`);
    console.log(`  State 4 → 5: +62 months`);
    console.log(`  State 5 → 6: +62 years`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
