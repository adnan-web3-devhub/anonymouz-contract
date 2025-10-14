import { expect } from "chai";
import { ethers } from "hardhat";
import { LumanaNFT, RoyaltySplitter, MockUSDT } from "../typechain-types";

describe("LumanaNFT", function () {
  let nft: LumanaNFT;
  let splitter: RoyaltySplitter;
  let usdt: MockUSDT;
  let owner: any, user: any, updater: any;

  beforeEach(async function () {
    [owner, user, updater] = await ethers.getSigners();

    // Deploy MockUSDT
    const MockUSDT = await ethers.getContractFactory("MockUSDT");
    usdt = await MockUSDT.deploy();
    await usdt.waitForDeployment();

    // Deploy Splitter
    const RoyaltySplitter = await ethers.getContractFactory("RoyaltySplitter");
    splitter = await RoyaltySplitter.deploy([owner.address, user.address], [5000, 5000], 500);
    await splitter.waitForDeployment();

    // Deploy NFT
    const LumanaNFT = await ethers.getContractFactory("LumanaNFT");
    nft = await LumanaNFT.deploy("LumanaNFT", "LUM", await usdt.getAddress(), [1000000, 2000000, 3000000], await splitter.getAddress());
    await nft.waitForDeployment();

    // Grant updater role
    const STATE_UPDATER_ROLE = await nft.STATE_UPDATER_ROLE();
    await nft.grantRole(STATE_UPDATER_ROLE, updater.address);

    // Mint USDT to user
    await usdt.mint(user.address, ethers.parseUnits("10000", 6));
  });

  describe("Minting", function () {
    it("Should mint with USDT approval", async function () {
      await usdt.connect(user).approve(await nft.getAddress(), ethers.parseUnits("1", 6));
      await expect(nft.connect(user).mintWithUSDT(0, 1)).to.emit(nft, "Minted");
      expect(await nft.ownerOf(1)).to.equal(user.address);
      expect(await nft.tierSupply(0)).to.equal(1);
    });

    it("Should reject insufficient allowance", async function () {
      await expect(nft.connect(user).mintWithUSDT(0, 1)).to.be.revertedWithCustomError(nft, "InsufficientAllowance");
    });

    it("Should reject sold out", async function () {
      await usdt.connect(user).approve(await nft.getAddress(), ethers.parseUnits("62", 6));
      await nft.connect(user).mintWithUSDT(0, 62);
      await expect(nft.connect(user).mintWithUSDT(0, 1)).to.be.revertedWithCustomError(nft, "SoldOut");
    });

    it("Should enforce tier caps", async function () {
      await usdt.connect(user).approve(await nft.getAddress(), ethers.parseUnits("62", 6));
      await nft.connect(user).mintWithUSDT(0, 62);
      expect(await nft.tierSupply(0)).to.equal(62);
    });
  });

  describe("State Management", function () {
    it("Should advance state only by updater", async function () {
      await expect(nft.connect(updater).advanceState()).to.emit(nft, "StateAdvanced");
      expect(await nft.currentState()).to.equal(1);
    });

    it("Should reject advance by non-updater", async function () {
      await expect(nft.connect(user).advanceState()).to.be.revertedWithCustomError(nft, "Unauthorized");
    });

    it("Should not advance beyond max state", async function () {
      for (let i = 0; i < 6; i++) {
        await nft.connect(updater).advanceState();
      }
      await expect(nft.connect(updater).advanceState()).to.be.revertedWithCustomError(nft, "InvalidState");
    });
  });

  describe("Royalties", function () {
    it("Should return royalty info", async function () {
      const [receiver, royalty] = await nft.royaltyInfo(1, 10000);
      expect(receiver).to.equal(await splitter.getAddress());
      expect(royalty).to.equal(500); // 5%
    });
  });

  describe("Pausable", function () {
    it("Should pause and unpause", async function () {
      await nft.pause();
      await usdt.connect(user).approve(await nft.getAddress(), ethers.parseUnits("1", 6));
      await expect(nft.connect(user).mintWithUSDT(0, 1)).to.be.revertedWith("Pausable: paused");
      await nft.unpause();
      await expect(nft.connect(user).mintWithUSDT(0, 1)).to.emit(nft, "Minted");
    });
  });

  describe("ERC-4906", function () {
    it("Should emit BatchMetadataUpdate on state advance", async function () {
      await expect(nft.connect(updater).advanceState()).to.emit(nft, "BatchMetadataUpdate");
    });
  });
});
