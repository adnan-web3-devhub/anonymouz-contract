// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LumanaNFT} from "../contracts/LumanaNFT.sol";
import {RoyaltySplitter} from "../contracts/RoyaltySplitter.sol";
import {MockUSDT} from "./MockUSDT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LumanaNFTTest is Test {
    LumanaNFT nft;
    RoyaltySplitter splitter;
    MockUSDT usdt;
    address owner = address(1);
    address user = address(2);
    address updater = address(3);

    function setUp() public {
        vm.startPrank(owner);
        usdt = new MockUSDT();
        address[] memory recipients = new address[](2);
        recipients[0] = owner;
        recipients[1] = user;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000;
        shares[1] = 5000;
        splitter = new RoyaltySplitter(recipients, shares, 500);
        uint256[3] memory prices = [uint256(1000000), 2000000, 3000000];
        nft = new LumanaNFT("LumanaNFT", "LUM", address(usdt), prices, address(splitter));
        nft.grantRole(nft.STATE_UPDATER_ROLE(), updater);
        usdt.mint(user, 400000000); // 400 USDT
        vm.stopPrank();
    }

    function testMintWithUSDT() public {
        vm.startPrank(user);
        usdt.approve(address(nft), 1000000);
        nft.mintWithUSDT(LumanaNFT.Tier.TIER1, 1);
        assertEq(nft.ownerOf(1), user);
        assertEq(nft.tierSupply(LumanaNFT.Tier.TIER1), 1);
        vm.stopPrank();
    }

    function testAdvanceState() public {
        vm.prank(updater);
        nft.advanceState();
        assertEq(nft.currentState(), 1);
    }

    function testCannotAdvanceBeyondMax() public {
        vm.startPrank(updater);
        for (uint8 i = 0; i < 6; i++) {
            nft.advanceState();
        }
        vm.expectRevert(LumanaNFT.InvalidState.selector);
        nft.advanceState();
        vm.stopPrank();
    }

    function testTotalSupplyInvariant() public {
        vm.startPrank(user);
        usdt.approve(address(nft), 186000000); // Enough for all
        nft.mintWithUSDT(LumanaNFT.Tier.TIER1, 62);
        usdt.approve(address(nft), 372000000); // Re-approve for TIER2 and TIER3
        nft.mintWithUSDT(LumanaNFT.Tier.TIER2, 62);
        nft.mintWithUSDT(LumanaNFT.Tier.TIER3, 62);
        assertEq(nft.totalSupply(), 186);
        vm.stopPrank();
    }

    function testRoyaltySplitter() public {
        vm.startPrank(user);
        usdt.approve(address(nft), 1000000);
        nft.mintWithUSDT(LumanaNFT.Tier.TIER1, 1);
        vm.stopPrank();

        vm.prank(owner);
        nft.withdrawUSDT();

        // USDT transferred to splitter, now distribute
        vm.prank(owner);
        splitter.distributeERC20(IERC20(address(usdt)), 1000000);

        assertEq(splitter.getPendingERC20(user, IERC20(address(usdt))), 25000); // 50% of 5% of 1M = 25000
    }

    function testMintExceedsSupply() public {
        vm.startPrank(user);
        usdt.approve(address(nft), 1000000 * 63); // More than max
        vm.expectRevert(LumanaNFT.SoldOut.selector);
        nft.mintWithUSDT(LumanaNFT.Tier.TIER1, 63);
        vm.stopPrank();
    }
}
