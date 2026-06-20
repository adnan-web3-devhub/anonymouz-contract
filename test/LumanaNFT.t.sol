// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LumanaNFT} from "../contracts/LumanaNFT.sol";
import {RoyaltySplitter} from "../contracts/RoyaltySplitter.sol";
import {MockUSDT} from "./MockUSDT.sol";
import {NonCompliantUSDT} from "./NonCompliantUSDT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract LumanaNFTTest is Test {
    // EIP-4906 event, re-declared locally for vm.expectEmit
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    LumanaNFT nft; // default: tier 1, 6-decimal USDT, price 1
    RoyaltySplitter splitter;
    MockUSDT usdt;

    address owner = address(1);
    address user = address(2);
    address updater = address(3);

    uint256 constant CHRISTMAS_TS = 1798132800;
    uint256 constant INDEPENDENCE_TS = 1811830800;

    function setUp() public {
        vm.startPrank(owner);
        usdt = new MockUSDT(6);

        address[] memory recipients = new address[](2);
        recipients[0] = owner;
        recipients[1] = user;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000;
        shares[1] = 5000;
        splitter = new RoyaltySplitter(recipients, shares);

        nft = _deployNft(1, address(usdt), 6, 1);
        nft.grantRole(nft.STATE_UPDATER_ROLE(), updater);
        usdt.mint(user, 62 * 10 ** 6); // 62 USDT
        vm.stopPrank();
    }

    function _deployNft(
        uint8 tier,
        address usdtAddr,
        uint8 decimals,
        uint256 price
    ) internal returns (LumanaNFT) {
        return
            new LumanaNFT(
                "4 THA LUMANA'I",
                "LUM",
                tier,
                usdtAddr,
                decimals,
                price,
                address(splitter)
            );
    }

    // ----------------------------------------------------------------- TIER

    function testTierImmutableSetCorrectly() public {
        assertEq(nft.TIER(), 1);
        assertEq(nft.tierName(), "AUMAGA");

        vm.prank(owner);
        LumanaNFT t2 = _deployNft(2, address(usdt), 18, 620);
        assertEq(t2.TIER(), 2);
        assertEq(t2.tierName(), "TULAFALE");

        vm.prank(owner);
        LumanaNFT t3 = _deployNft(3, address(usdt), 6, 62);
        assertEq(t3.TIER(), 3);
        assertEq(t3.tierName(), "ALI'I");
    }

    function testRevertsOnTierZero() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.InvalidTier.selector);
        _deployNft(0, address(usdt), 6, 1);
    }

    function testRevertsOnTierFour() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.InvalidTier.selector);
        _deployNft(4, address(usdt), 6, 1);
    }

    // --------------------------------------------------- M1: CTOR VALIDATION

    function testConstructorRevertsZeroUsdt() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.ZeroAddress.selector);
        _deployNft(1, address(0), 6, 1);
    }

    function testConstructorRevertsZeroSplitter() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.ZeroAddress.selector);
        new LumanaNFT("L", "L", 1, address(usdt), 6, 1, address(0));
    }

    function testConstructorRevertsZeroPrice() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.InvalidPrice.selector);
        _deployNft(1, address(usdt), 6, 0);
    }

    function testConstructorRevertsDecimals19() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.InvalidDecimals.selector);
        _deployNft(1, address(usdt), 19, 1);
    }

    // --------------------------------------------------------------- SUPPLY

    function testMintWithUSDT() public {
        vm.startPrank(user);
        uint256 totalPrice = nft.price() * 1 * (10 ** nft.usdtDecimals());
        usdt.approve(address(nft), totalPrice);
        nft.mintWithUSDT(1);
        assertEq(nft.ownerOf(1), user);
        assertEq(nft.supply(), 1);
        vm.stopPrank();
    }

    function testMaxSupplyCap() public {
        assertEq(nft.MAX_SUPPLY(), 62);
        vm.startPrank(user);
        uint256 totalPrice = nft.price() * 62 * (10 ** nft.usdtDecimals());
        usdt.approve(address(nft), totalPrice);
        nft.mintWithUSDT(62);
        assertEq(nft.totalSupply(), 62);
        vm.stopPrank();
    }

    function testMintExceedsSupplyReverts() public {
        vm.startPrank(user);
        usdt.approve(address(nft), type(uint256).max);
        usdt.mint(user, 1000 * 10 ** 6);
        vm.expectRevert(LumanaNFT.SoldOut.selector);
        nft.mintWithUSDT(63);
        vm.stopPrank();
    }

    // ----------------------------------------------------- MINT COST MATH

    function testMintCostMath6Decimals() public {
        vm.prank(owner);
        LumanaNFT t3 = _deployNft(3, address(usdt), 6, 62);

        // Pay from a non-recipient so the full price leaves the buyer's wallet.
        address buyer = address(0xB0B);
        uint256 expected = 62 * 1 * (10 ** 6); // 62_000_000
        vm.startPrank(buyer);
        usdt.mint(buyer, expected);
        usdt.approve(address(t3), expected);
        uint256 balBefore = usdt.balanceOf(buyer);
        t3.mintWithUSDT(1);
        assertEq(balBefore - usdt.balanceOf(buyer), expected);
        vm.stopPrank();
    }

    function testMintCostMath18Decimals() public {
        MockUSDT usdt18 = new MockUSDT(18);
        vm.prank(owner);
        LumanaNFT t2 = _deployNft(2, address(usdt18), 18, 620);

        uint256 expected = 620 * 1 * (10 ** 18); // 620e18
        assertEq(t2.usdtDecimals(), 18);

        // Pay from a non-recipient so the full price leaves the buyer's wallet.
        address buyer = address(0xB0B);
        vm.startPrank(buyer);
        usdt18.mint(buyer, expected);
        usdt18.approve(address(t2), expected);
        uint256 balBefore = usdt18.balanceOf(buyer);
        t2.mintWithUSDT(1);
        assertEq(balBefore - usdt18.balanceOf(buyer), expected);
        assertEq(t2.ownerOf(1), buyer);
        vm.stopPrank();
    }

    // ------------------------------------------------------- CURRENT STATE

    function testCurrentStateBeforeChristmas() public {
        vm.warp(CHRISTMAS_TS - 1);
        assertEq(nft.currentState(), 1);
    }

    function testCurrentStateAtChristmas() public {
        vm.warp(CHRISTMAS_TS);
        assertEq(nft.currentState(), 2);
    }

    function testCurrentStateBetweenThresholds() public {
        vm.warp(INDEPENDENCE_TS - 1);
        assertEq(nft.currentState(), 2);
    }

    function testCurrentStateAtIndependence() public {
        vm.warp(INDEPENDENCE_TS);
        assertEq(nft.currentState(), 3);
    }

    function testCurrentStateAfterIndependence() public {
        vm.warp(INDEPENDENCE_TS + 365 days);
        assertEq(nft.currentState(), 3);
    }

    // ------------------------------------------------------------ TOKENURI

    function testTokenURIPerState() public {
        vm.startPrank(owner);
        nft.setBaseURI(1, "ipfs://state1/");
        nft.setBaseURI(2, "ipfs://state2/");
        nft.setBaseURI(3, "ipfs://state3/");
        vm.stopPrank();

        vm.startPrank(user);
        usdt.approve(address(nft), nft.price() * (10 ** nft.usdtDecimals()));
        nft.mintWithUSDT(1);
        vm.stopPrank();

        vm.warp(CHRISTMAS_TS - 1);
        assertEq(nft.tokenURI(1), "ipfs://state1/1");

        vm.warp(CHRISTMAS_TS);
        assertEq(nft.tokenURI(1), "ipfs://state2/1");

        vm.warp(INDEPENDENCE_TS);
        assertEq(nft.tokenURI(1), "ipfs://state3/1");
    }

    function testTokenURIEmptyWhenUnset() public {
        vm.startPrank(user);
        usdt.approve(address(nft), nft.price() * (10 ** nft.usdtDecimals()));
        nft.mintWithUSDT(1);
        vm.stopPrank();

        vm.warp(CHRISTMAS_TS - 1);
        assertEq(nft.tokenURI(1), "");
    }

    function testSetBaseURIInvalidStateReverts() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.InvalidState.selector);
        nft.setBaseURI(0, "x");

        vm.prank(owner);
        vm.expectRevert(LumanaNFT.InvalidState.selector);
        nft.setBaseURI(4, "x");
    }

    // -------------------------------------------------- METADATA REFRESH

    function testTriggerMetadataRefreshEmits() public {
        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(1, 62);
        vm.prank(updater);
        nft.triggerMetadataRefresh();
    }

    function testTriggerMetadataRefreshRevertsForNonUpdater() public {
        bytes32 role = nft.STATE_UPDATER_ROLE();
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                user,
                role
            )
        );
        nft.triggerMetadataRefresh();
    }

    // --------------------------------------------------------- ROYALTIES

    function testRoyaltyFivePercentToSplitter() public {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10000);
        assertEq(receiver, address(splitter));
        assertEq(amount, 500); // 5% of 10000
    }

    /// @dev Royalties arrive at the splitter directly (EIP-2981 receiver) and are
    ///      credited by MEASURED balance, then claimed pull-style.
    function testRoyaltyDistributionByMeasuredReceipt() public {
        vm.prank(user);
        usdt.transfer(address(splitter), 1 * 10 ** 6); // simulate a royalty payment

        splitter.distributeERC20(IERC20(address(usdt)));

        assertEq(splitter.getPendingERC20(owner, IERC20(address(usdt))), 500000);
        assertEq(splitter.getPendingERC20(user, IERC20(address(usdt))), 500000);
    }

    // ------------------------------------------- H1 REGRESSION (over-credit)

    /// @dev The old drain relied on a forgeable `amount` arg. The function now takes only
    ///      the token; distribution equals only funds that truly arrived, and re-calling
    ///      without new funds reverts. No way to over-credit.
    function testH1CannotOverCreditViaForgedAmount() public {
        vm.prank(user);
        usdt.transfer(address(splitter), 1 * 10 ** 6);

        splitter.distributeERC20(IERC20(address(usdt)));
        // recipient share is exactly half of the 1 USDT that arrived
        assertEq(splitter.getPendingERC20(user, IERC20(address(usdt))), 500000);

        // Re-calling without new funds credits nothing (cannot inflate accounting).
        vm.expectRevert(RoyaltySplitter.NothingToDistribute.selector);
        splitter.distributeERC20(IERC20(address(usdt)));

        // A recipient can only ever withdraw their measured share, never the whole balance.
        vm.prank(user);
        splitter.withdrawERC20(IERC20(address(usdt)));
        assertEq(usdt.balanceOf(user) - (62 * 10 ** 6 - 1 * 10 ** 6), 500000);
        // 500000 still owed to owner remains in the splitter
        assertEq(usdt.balanceOf(address(splitter)), 500000);
    }

    // ----------------------- UNIFIED FLOW: mint auto-pushes to wallets in-tx

    /// @dev mintWithUSDT forwards payment to the splitter, which PUSHES each recipient's
    ///      share straight to their wallet in the SAME tx — no pending balances, no withdraw.
    function testMintAutoPushesToRecipients() public {
        // Recipients are owner (50%) and user (50%); user is also the payer.
        uint256 ownerBefore = usdt.balanceOf(owner);
        uint256 userBefore = usdt.balanceOf(user);

        vm.startPrank(user);
        usdt.approve(address(nft), 1 * 10 ** 6);
        nft.mintWithUSDT(1);
        vm.stopPrank();

        // Nothing is held by the NFT or left sitting in the splitter.
        assertEq(usdt.balanceOf(address(nft)), 0);
        assertEq(usdt.balanceOf(address(splitter)), 0);

        // Each recipient's share landed directly in their wallet.
        assertEq(usdt.balanceOf(owner) - ownerBefore, 500000);
        // user paid 1 USDT then received their 0.5 USDT share back (net -0.5).
        assertEq(userBefore - usdt.balanceOf(user), 500000);

        // No pending balances exist under the push model.
        assertEq(splitter.getPendingERC20(owner, IERC20(address(usdt))), 0);
        assertEq(splitter.getPendingERC20(user, IERC20(address(usdt))), 0);
    }

    /// @dev After the push on mint, the splitter holds nothing, so there is no surplus to
    ///      rescue — proving mint revenue went to recipients, not the splitter.
    function testMintLeavesNoSweepableSurplus() public {
        vm.startPrank(user);
        usdt.approve(address(nft), 1 * 10 ** 6);
        nft.mintWithUSDT(1);
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(RoyaltySplitter.NoSurplus.selector);
        splitter.rescueERC20(IERC20(address(usdt)), owner);
    }

    /// @dev withdrawUSDT remains a safety sweep for USDT sent to the NFT by mistake:
    ///      it routes the stray balance to the splitter, which pushes it to wallets.
    function testWithdrawUSDTSweepsStrayUSDT() public {
        uint256 ownerBefore = usdt.balanceOf(owner);
        uint256 userBefore = usdt.balanceOf(user);

        // Simulate USDT accidentally sent directly to the NFT contract.
        vm.prank(user);
        usdt.transfer(address(nft), 1 * 10 ** 6);

        vm.expectEmit(true, false, false, true, address(nft));
        emit LumanaNFT.Withdrawn(address(splitter), 1 * 10 ** 6);
        vm.prank(owner);
        nft.withdrawUSDT();

        assertEq(usdt.balanceOf(address(nft)), 0);
        assertEq(usdt.balanceOf(address(splitter)), 0);
        assertEq(usdt.balanceOf(owner) - ownerBefore, 500000);
        // user sent away 1 USDT, then got their 0.5 USDT share pushed back (net -0.5).
        assertEq(userBefore - usdt.balanceOf(user), 500000);
    }

    /// @dev Push path drains any rounding dust to the LAST recipient so the splitter is
    ///      fully emptied even when the amount isn't perfectly divisible by the shares.
    function testPushSendsDustToLastRecipient() public {
        // 3-way splitter with uneven shares so integer division leaves dust.
        address r3 = address(99);
        address[] memory recipients = new address[](3);
        recipients[0] = owner;
        recipients[1] = user;
        recipients[2] = r3;
        uint256[] memory shares = new uint256[](3);
        shares[0] = 3333;
        shares[1] = 3333;
        shares[2] = 3334;
        vm.prank(owner);
        RoyaltySplitter sp = new RoyaltySplitter(recipients, shares);

        uint256 ownerBefore = usdt.balanceOf(owner);
        uint256 r3Before = usdt.balanceOf(r3);

        // Send 100 wei: shares give 33/33/34 -> 1 wei dust to last recipient.
        vm.prank(user);
        usdt.transfer(address(sp), 100);
        sp.distributeERC20Push(IERC20(address(usdt)));

        assertEq(usdt.balanceOf(address(sp)), 0); // fully drained
        assertEq(usdt.balanceOf(owner) - ownerBefore, 33);
        assertEq(usdt.balanceOf(r3) - r3Before, 34); // remainder + dust
    }

    /// @dev Secondary path: USDT paid directly to the splitter (e.g. by a marketplace) can
    ///      still be credited pull-based via distributeERC20 / withdrawERC20.
    function testSecondaryRoyaltyDirectInflowCreditedByShare() public {
        vm.prank(user);
        usdt.transfer(address(splitter), 2 * 10 ** 6);

        splitter.distributeERC20(IERC20(address(usdt)));

        assertEq(splitter.getPendingERC20(owner, IERC20(address(usdt))), 1_000_000);
        assertEq(splitter.getPendingERC20(user, IERC20(address(usdt))), 1_000_000);
    }

    function testWithdrawUSDTZeroBalanceReverts() public {
        vm.prank(owner);
        vm.expectRevert(LumanaNFT.NothingToWithdraw.selector);
        nft.withdrawUSDT();
    }

    // ---------------------------------------------------- SPLITTER RESCUE

    function testRescueERC20SweepsStraySurplus() public {
        vm.prank(user);
        usdt.transfer(address(splitter), 1 * 10 ** 6); // stray, never distributed

        vm.prank(owner);
        splitter.rescueERC20(IERC20(address(usdt)), owner);
        assertEq(usdt.balanceOf(address(splitter)), 0);
    }

    function testRescueERC20DoesNotTouchAccounted() public {
        // 1 USDT accounted via distribute, then 1 USDT stray
        vm.prank(user);
        usdt.transfer(address(splitter), 1 * 10 ** 6);
        splitter.distributeERC20(IERC20(address(usdt)));

        vm.prank(user);
        usdt.transfer(address(splitter), 1 * 10 ** 6); // stray surplus

        vm.prank(owner);
        splitter.rescueERC20(IERC20(address(usdt)), owner);

        // Only the stray 1 USDT swept; the accounted 1 USDT stays claimable.
        assertEq(usdt.balanceOf(address(splitter)), 1 * 10 ** 6);
        assertEq(splitter.getPendingERC20(owner, IERC20(address(usdt))), 500000);
    }

    function testRescueERC20RevertsWhenNoSurplus() public {
        vm.prank(owner);
        vm.expectRevert(RoyaltySplitter.NoSurplus.selector);
        splitter.rescueERC20(IERC20(address(usdt)), owner);
    }

    // ============================================================ C1 PROOF
    // Every USDT movement must work against a non-returning (ETH-Tether) token.

    function _deploySplitter() internal returns (RoyaltySplitter) {
        address[] memory recipients = new address[](2);
        recipients[0] = owner;
        recipients[1] = user;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000;
        shares[1] = 5000;
        return new RoyaltySplitter(recipients, shares);
    }

    function testC1MintAndWithdrawAgainstNonCompliantUSDT() public {
        NonCompliantUSDT ncusdt = new NonCompliantUSDT(6);
        vm.prank(owner);
        RoyaltySplitter sp = _deploySplitter();

        vm.prank(owner);
        LumanaNFT n = new LumanaNFT(
            "L",
            "L",
            1,
            address(ncusdt),
            6,
            10,
            address(sp)
        );

        uint256 cost = 10 * 10 ** 6;
        ncusdt.mint(user, cost);

        // mint (safeTransferFrom + auto-push) works despite no return data:
        // payment is forwarded to the splitter and pushed to wallets in the same tx.
        vm.startPrank(user);
        ncusdt.approve(address(n), cost);
        n.mintWithUSDT(1);
        vm.stopPrank();
        assertEq(n.ownerOf(1), user);
        assertEq(ncusdt.balanceOf(address(n)), 0);
        assertEq(ncusdt.balanceOf(address(sp)), 0);
        // Shares pushed straight to recipient wallets (owner 50%, user 50%).
        assertEq(ncusdt.balanceOf(owner), 5 * 10 ** 6);
        assertEq(ncusdt.balanceOf(user), 5 * 10 ** 6); // paid 10, got 5 back
    }

    function testC1SplitterWithdrawalsAgainstNonCompliantUSDT() public {
        NonCompliantUSDT ncusdt = new NonCompliantUSDT(6);
        vm.prank(owner);
        RoyaltySplitter sp = _deploySplitter();

        // royalty arrives at splitter, distribute by measured receipt
        ncusdt.mint(address(sp), 4 * 10 ** 6);
        sp.distributeERC20(IERC20(address(ncusdt)));

        // withdrawERC20 (safeTransfer) works against non-returning token
        vm.prank(owner);
        sp.withdrawERC20(IERC20(address(ncusdt)));
        assertEq(ncusdt.balanceOf(owner), 2 * 10 ** 6);

        // withdrawBatch (safeTransfer) works for the other recipient
        IERC20[] memory toks = new IERC20[](1);
        toks[0] = IERC20(address(ncusdt));
        vm.prank(user);
        sp.withdrawBatch(toks);
        assertEq(ncusdt.balanceOf(user), 2 * 10 ** 6);

        // rescueERC20 (safeTransfer) works for stray surplus
        ncusdt.mint(address(sp), 1 * 10 ** 6);
        vm.prank(owner);
        sp.rescueERC20(IERC20(address(ncusdt)), owner);
        assertEq(ncusdt.balanceOf(owner), 3 * 10 ** 6);
    }
}
