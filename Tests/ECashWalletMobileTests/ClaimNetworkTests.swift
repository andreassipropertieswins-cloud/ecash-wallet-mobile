// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
import WalletService
@testable import ECashWalletMobile

/// The investor claim follows the selected wallet's eCash chain, and otherwise goes to the real
/// chain. It is its own rule, independent of `currentEcash` (Jake, 2026-10-29).
@Suite struct ClaimNetworkTests {
    @Test func followsTheSelectedECashChain() {
        #expect(ClaimNetwork.target(selected: .ecashBeta) == .ecashBeta)
        #expect(ClaimNetwork.target(selected: .ecashMainnet) == .ecashMainnet)
    }

    @Test func anythingElseClaimsOnMainnet() {
        for other: WalletNetwork? in [.bitcoin, .signet, .thunder, .ecash, nil] {
            #expect(ClaimNetwork.target(selected: other) == .ecashMainnet, "\(String(describing: other))")
        }
    }

    /// The fork latch (closed here) has no say: a claim from a mainnet wallet goes to mainnet.
    @Test func doesNotWaitForTheForkLatch() {
        EcashMainnetLaunch.resetForTesting(offered: true)
        defer { EcashMainnetLaunch.resetForTesting(offered: false) }
        #expect(!EcashMainnetLaunch.isDefault)
        #expect(ClaimNetwork.target(selected: .ecashMainnet) == .ecashMainnet)
        #expect(ClaimNetwork.target(selected: nil) == .ecashMainnet)
    }
}
