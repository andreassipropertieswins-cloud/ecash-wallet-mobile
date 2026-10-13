// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import WalletService

/// The pure coin-split classifier. Since 2026-10-10 a coin is classified ONLY by what Bitcoin's
/// explorer said about it — no height heuristic — so these pin that an unchecked coin never needs
/// splitting and never counts as safe. Money-adjacent, so exhaustively unit-tested away from BDK.
final class SplitSummaryTests: XCTestCase {

    private func utxo(_ sats: Int64, _ txid: String = "t", _ vout: Int32 = Int32(0)) -> SplitUtxo {
        SplitUtxo(sats: sats, txid: txid, vout: vout)
    }

    /// No answers from Bitcoin → nothing is flagged, and nothing is called safe either.
    func testUncheckedCoinsAreUnverifiedNotFlagged() {
        let s = SplitSummary.classify([utxo(100, "a"), utxo(200, "b")])
        XCTAssertEqual(s.spendableSats, 300)
        XCTAssertEqual(s.needsSplitSats, 0)
        XCTAssertEqual(s.needsSplitCount, 0)
        XCTAssertEqual(s.unverifiedSats, 300)
        XCTAssertEqual(s.unverifiedCount, 2)
    }

    func testKnownSharedNeedsSplitting() {
        let s = SplitSummary.classify([utxo(700, "abc", Int32(1))], knownShared: ["abc:1"])
        XCTAssertEqual(s.needsSplitSats, 700)
        XCTAssertEqual(s.needsSplitCount, 1)
        XCTAssertEqual(s.unverifiedCount, 0)
    }

    func testKnownSafeIsNeitherFlaggedNorUnverified() {
        let s = SplitSummary.classify([utxo(400, "def")], knownSafe: ["def:0"])
        XCTAssertEqual(s.needsSplitCount, 0)
        XCTAssertEqual(s.needsSplitSats, 0)
        XCTAssertEqual(s.unverifiedCount, 0)                   // verified, not merely unchecked
        XCTAssertEqual(s.spendableSats, 400)                   // still spendable either way
    }

    func testMixedVerdicts() {
        let s = SplitSummary.classify([utxo(100, "a"), utxo(200, "b"), utxo(300, "c")],
                                      knownShared: ["a:0"], knownSafe: ["b:0"])
        XCTAssertEqual(s.spendableSats, 600)
        XCTAssertEqual(s.needsSplitSats, 100)
        XCTAssertEqual(s.needsSplitCount, 1)
        XCTAssertEqual(s.unverifiedSats, 300)
        XCTAssertEqual(s.unverifiedCount, 1)
    }

    /// Verified answers must not leak between coins — matching is per outpoint, and a shared txid
    /// with a different vout is a different coin.
    func testVerdictsMatchPerOutpointNotPerTxid() {
        let a = utxo(100, "same", Int32(0))
        let b = utxo(200, "same", Int32(1))
        let s = SplitSummary.classify([a, b], knownShared: ["same:1"])
        XCTAssertEqual(s.needsSplitSats, 200)                  // only vout 1
        XCTAssertEqual(s.needsSplitCount, 1)
        XCTAssertEqual(s.unverifiedSats, 100)                  // vout 0 remains unchecked
    }

    func testEmptyIsZero() {
        let s = SplitSummary.classify([])
        XCTAssertEqual(s.spendableSats, 0)
        XCTAssertEqual(s.needsSplitSats, 0)
        XCTAssertEqual(s.needsSplitCount, 0)
        XCTAssertEqual(s.unverifiedCount, 0)
    }

    func testForkHeightRegistryValues() {
        // Both eCash chains have a fork height (alphanet, betanet); used to mark pre-fork history.
        XCTAssertEqual(NetworkRegistry.forkHeight(for: WalletNetwork.ecash), 963_648)
        XCTAssertEqual(NetworkRegistry.forkHeight(for: WalletNetwork.ecashBeta), 967_680)
        XCTAssertNil(NetworkRegistry.forkHeight(for: WalletNetwork.bitcoin))
        XCTAssertNil(NetworkRegistry.forkHeight(for: WalletNetwork.signet))
        XCTAssertNil(NetworkRegistry.forkHeight(for: WalletNetwork.thunder))
    }

    // MARK: - Remote fork height (drynet rollover)

    /// The fork height is NOT a constant: drynet2/3 forked at 957,600 and drynet4 at 961,632, and the
    /// remote config repoints `.ecash` at whichever chain is live. Split classification no longer uses
    /// it, but transaction history still marks pre-fork txs against the applied height.
    func testRemoteForkHeightOverridesTheBundledOne() {
        let bundled = NetworkRegistry.forkHeight(for: WalletNetwork.ecash) ?? Int64(0)
        XCTAssertEqual(bundled, Int64(963_648))   // alphanet

        WalletManager.setRemoteForkHeightForTesting(Int64(961_632), network: WalletNetwork.ecash)
        defer { WalletManager.clearRemoteForkHeightForTesting(network: WalletNetwork.ecash) }
        XCTAssertEqual(WalletManager.effectiveForkHeight(for: WalletNetwork.ecash), Int64(961_632))

    }

    /// A malformed payload must not be able to move the boundary to zero — that would mark every tx
    /// post-fork.
    func testNonPositiveRemoteForkHeightIsIgnored() {
        WalletManager.setRemoteForkHeightForTesting(Int64(961_632), network: WalletNetwork.ecash)
        defer { WalletManager.clearRemoteForkHeightForTesting(network: WalletNetwork.ecash) }
        WalletManager.setRemoteForkHeightForTesting(Int64(-1), network: WalletNetwork.ecash)
        XCTAssertEqual(WalletManager.effectiveForkHeight(for: WalletNetwork.ecash), Int64(961_632))
    }
}
