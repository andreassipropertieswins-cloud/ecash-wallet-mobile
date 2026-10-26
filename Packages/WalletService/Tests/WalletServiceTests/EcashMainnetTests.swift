// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import WalletService

/// The real eCash mainnet case (`.ecashMainnet`): its compiled consensus values, and the two gates
/// that decide when it is offered and when it becomes the default (`EcashMainnetLaunch`).
///
/// The values are checked against the node source (github.com/ecash-com/bitcoin master, read
/// 2026-10-21), not against each other: fork height `consensus.EcashHeight = 973728`,
/// `OP_DRIVECHAIN = OP_NOP8` (0xb7), and replay protection `nLockTime == LOCKTIME_THRESHOLD - 2`.
final class EcashMainnetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        EcashMainnetLaunch.resetForTesting(offered: false)
        WalletManager.clearRemoteForkHeightForTesting(network: WalletNetwork.ecashMainnet)
    }

    override func tearDown() {
        EcashMainnetLaunch.resetForTesting(offered: false)
        WalletManager.clearRemoteForkHeightForTesting(network: WalletNetwork.ecashMainnet)
        super.tearDown()
    }

    // MARK: - Identity and derivation

    /// The rawValue is persisted in the wallet store and enforced by `check_network` — fixed forever.
    func testRawValueIsStable() {
        XCTAssertEqual(WalletNetwork.ecashMainnet.rawValue, "ecashMainnet")
        XCTAssertEqual(WalletNetwork(rawValue: "ecashMainnet"), WalletNetwork.ecashMainnet)
        // And the test forks keep theirs: betanet is never repurposed.
        XCTAssertEqual(WalletNetwork(rawValue: "ecashBeta"), WalletNetwork.ecashBeta)
        XCTAssertEqual(WalletNetwork(rawValue: "ecash"), WalletNetwork.ecash)
    }

    func testDerivesExactlyLikeTheTestForksAndBitcoin() {
        let p = NetworkRegistry.params(for: WalletNetwork.ecashMainnet)
        XCTAssertEqual(p.coinType, Int32(0))
        XCTAssertEqual(p.addressHRP, "bc")
        XCTAssertEqual(p.unitLabel, "ECX")
        XCTAssertEqual(p.subUnitLabel, "szat")
        XCTAssertEqual(p.defaultBackendKind, "esplora")
        XCTAssertTrue(WalletNetwork.ecashMainnet.sharesKeys(with: WalletNetwork.ecashBeta))
        XCTAssertTrue(WalletNetwork.ecashMainnet.sharesKeys(with: WalletNetwork.ecash))
        XCTAssertTrue(WalletNetwork.ecashMainnet.sharesKeys(with: WalletNetwork.bitcoin))
        XCTAssertFalse(WalletNetwork.ecashMainnet.sharesKeys(with: WalletNetwork.signet))
    }

    func testIsRealMoney() {
        XCTAssertTrue(WalletNetwork.ecashMainnet.isMainnet)
        XCTAssertTrue(WalletNetwork.bitcoin.isMainnet)
        XCTAssertFalse(WalletNetwork.ecashBeta.isMainnet)
        XCTAssertFalse(WalletNetwork.ecash.isMainnet)
    }

    func testSupportsCoinSplitting() {
        XCTAssertTrue(WalletNetwork.ecashMainnet.supportsCoinSplit)
    }

    // MARK: - Consensus values (compiled, never from config)

    /// `LOCKTIME_THRESHOLD - 2`. The test forks' `- 1` is NOT valid on the real chain: there it reads
    /// as a block height ~500M blocks out and the tx is rejected as non-final.
    func testReplayMarkerIsOneBelowTheTestForks() {
        XCTAssertEqual(NetworkRegistry.replayProtectionLockHeight(for: WalletNetwork.ecashMainnet), UInt32(499_999_998))
        XCTAssertEqual(NetworkRegistry.replayProtectionLockHeight(for: WalletNetwork.ecashBeta), UInt32(499_999_999))
        XCTAssertEqual(NetworkRegistry.replayProtectionLockHeight(for: WalletNetwork.ecash), UInt32(499_999_999))
        XCTAssertNil(NetworkRegistry.replayProtectionLockHeight(for: WalletNetwork.bitcoin))
    }

    func testForkHeightIsTheNodesEcashHeight() {
        XCTAssertEqual(NetworkRegistry.forkHeight(for: WalletNetwork.ecashMainnet), Int64(973_728))
        XCTAssertNotEqual(NetworkRegistry.forkHeight(for: WalletNetwork.ecashMainnet), NetworkRegistry.forkHeight(for: WalletNetwork.ecashBeta))
    }

    func testDrivechainOpcodeIsNop8() {
        XCTAssertEqual(Drivechain.opcode(for: WalletNetwork.ecashMainnet), UInt8(0xb7))
    }

    /// Alphanet (`.ecash`) was retired 2026-10-26: never offered, but its persisted rawValue must
    /// keep decoding so existing alphanet wallets load.
    func testAlphanetIsRetiredButStillDecodes() {
        XCTAssertFalse(WalletNetwork.selectable.contains(WalletNetwork.ecash))
        XCTAssertEqual(WalletNetwork(rawValue: "ecash"), WalletNetwork.ecash)
        XCTAssertNotEqual(WalletNetwork.ecash, WalletNetwork.ecashMainnet)
    }

    // MARK: - Launch gates

    /// Picker order (Jake, 2026-10-26): eCash chains first, then Bitcoin, then the dev networks;
    /// the real fork slots in after betanet once offered. The default is `currentEcash`, not position.
    func testPickerOrderPutsTheECashChainsFirst() {
        XCTAssertEqual(WalletNetwork.selectable,
                       [WalletNetwork.ecashBeta, WalletNetwork.bitcoin, WalletNetwork.signet, WalletNetwork.thunder])
        EcashMainnetLaunch.resetForTesting(offered: true)
        XCTAssertEqual(WalletNetwork.selectable,
                       [WalletNetwork.ecashBeta, WalletNetwork.ecashMainnet, WalletNetwork.bitcoin,
                        WalletNetwork.signet, WalletNetwork.thunder])
    }

    func testHiddenUntilTheConfigPublishesIt() {
        XCTAssertFalse(EcashMainnetLaunch.isOffered)
        XCTAssertFalse(WalletNetwork.selectable.contains(WalletNetwork.ecashMainnet))
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashBeta)
        // The chain being past the fork changes nothing while the config hasn't published the entry.
        XCTAssertFalse(EcashMainnetLaunch.recordObservedTip(height: Int64(999_999)) && EcashMainnetLaunch.isDefault)
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashBeta)
    }

    func testOfferedOnceTheConfigPublishesItButNotYetTheDefault() {
        EcashMainnetLaunch.resetForTesting(offered: true)
        XCTAssertTrue(EcashMainnetLaunch.isOffered)
        XCTAssertTrue(WalletNetwork.selectable.contains(WalletNetwork.ecashMainnet))
        XCTAssertTrue(WalletNetwork.selectable.contains(WalletNetwork.ecashBeta), "betanet stays")
        XCTAssertFalse(EcashMainnetLaunch.isDefault)
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashBeta)
    }

    func testBecomesTheDefaultOnlyAtTheForkHeight() {
        EcashMainnetLaunch.resetForTesting(offered: true)
        XCTAssertFalse(EcashMainnetLaunch.recordObservedTip(height: Int64(973_727)))
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashBeta)

        XCTAssertTrue(EcashMainnetLaunch.recordObservedTip(height: Int64(973_728)))
        XCTAssertTrue(EcashMainnetLaunch.isDefault)
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashMainnet)
        // Latched: a later, lower (or repeated) observation doesn't flip it back, and reports no change.
        XCTAssertFalse(EcashMainnetLaunch.recordObservedTip(height: Int64(973_728)))
        XCTAssertFalse(EcashMainnetLaunch.recordObservedTip(height: Int64(1)))
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashMainnet)
    }

    /// The config's `fork_height` for the mainnet entry is the one the gate compares against.
    func testTheConfigsForkHeightWins() {
        EcashMainnetLaunch.resetForTesting(offered: true)
        WalletManager.setRemoteForkHeightForTesting(Int64(980_000), network: WalletNetwork.ecashMainnet)
        XCTAssertEqual(EcashMainnetLaunch.forkHeight, Int64(980_000))
        XCTAssertFalse(EcashMainnetLaunch.recordObservedTip(height: Int64(973_728)))
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashBeta)
        XCTAssertTrue(EcashMainnetLaunch.recordObservedTip(height: Int64(980_000)))
        XCTAssertEqual(WalletNetwork.currentEcash, WalletNetwork.ecashMainnet)
    }

    func testEverySelectableNetworkResolvesWhileMainnetIsOffered() {
        EcashMainnetLaunch.resetForTesting(offered: true)
        for network in WalletNetwork.selectable {
            let kind = NetworkRegistry.params(for: network).defaultBackendKind
            XCTAssertNotNil(WalletBackend.Kind.from(kind), "\(network.rawValue)")
        }
    }
}
