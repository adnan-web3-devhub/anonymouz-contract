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
        uint256 price = 1; // 1 USDT (whole units)
        nft = new LumanaNFT("LumanaNFT", "LUM", address(usdt), price, address(splitter));
        nft.grantRole(nft.STATE_UPDATER_ROLE(), updater);
        usdt.mint(user, 62000000); // 62 USDT for testTotalSupplyInvariant
        vm.stopPrank();
    }

    function testMintWithUSDT() public {
        vm.startPrank(user);
        uint256 totalPrice = nft.price() * 1 * (10 ** nft.decimals()); // 1 * 1 * 1000000 = 1000000
        usdt.approve(address(nft), totalPrice);
        nft.mintWithUSDT(1);
        assertEq(nft.ownerOf(1), user);
        assertEq(nft.supply(), 1);
        vm.stopPrank();
    }

    function testAdvanceState() public {
        vm.warp(10000); // Set block.timestamp to 10000 to avoid underflow
        vm.prank(owner);
        nft.setLaunchTime(10000 - 63 * 60 - 1); // Set launch time to just over 62 minutes ago
        vm.warp(10001); // Advance time by 1 second to ensure condition
        nft.advanceState();
        assertEq(nft.getCurrentState(), 1);
    }

    function testCannotAdvanceBeyondMax() public {
        vm.warp(2000000000); // Set block.timestamp to a large value to avoid underflow
        vm.prank(owner);
        nft.setLaunchTime(2000000000 - 62 * 365 * 24 * 3600); // Set launch time to 62 years ago
        vm.startPrank(owner);
        for (uint8 i = 0; i < 6; i++) {
            nft.advanceState();
        }
        vm.expectRevert(LumanaNFT.InvalidState.selector);
        nft.advanceState();
        vm.stopPrank();
    }

    function testTotalSupplyInvariant() public {
        vm.startPrank(user);
        uint256 totalPrice = nft.price() * 62 * (10 ** nft.decimals()); // 62 * 1 * 1000000 = 62000000
        usdt.approve(address(nft), totalPrice);
        nft.mintWithUSDT(62);
        assertEq(nft.totalSupply(), 62);
        vm.stopPrank();
    }

    function testRoyaltySplitter() public {
        vm.startPrank(user);
        usdt.approve(address(nft), 1000000);
        nft.mintWithUSDT(1);
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
        nft.mintWithUSDT(63);
        vm.stopPrank();
    }
}
