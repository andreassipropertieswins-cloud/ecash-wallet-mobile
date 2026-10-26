// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Testing
import WalletService
@testable import ECashWalletMobile

/// The create/import picker rows read `<name> (<unit>)`, with the eCash test forks branded
/// "eCash …" (Jake, 2026-10-26: "eCash Betanet (ECX)", "eCash (ECX)", "Bitcoin (BTC)").
@Suite(.serialized)
struct NetworkSelectorLabelTests {

    private static func reset() {
        for network in WalletNetwork.allCases {
            WalletManager.setRemoteDisplayNameForTesting(nil, network: network)
        }
    }

    @Test func bundledNames() {
        Self.reset()
        #expect(NetworkSelector.label(for: .ecashBeta) == "eCash Betanet (ECX)")
        #expect(NetworkSelector.label(for: .ecashMainnet) == "eCash (ECX)")
        #expect(NetworkSelector.label(for: .bitcoin) == "Bitcoin (BTC)")
        #expect(NetworkSelector.label(for: .signet) == "L2L Signet (sBTC)")
        #expect(NetworkSelector.label(for: .thunder) == "Thunder Betanet (ECX)")
    }

    /// The live config names betanet "Betanet" and the real fork "eCash": branded once, never doubled.
    @Test func liveConfigNamesAreBrandedOnce() {
        Self.reset()
        WalletManager.setRemoteDisplayNameForTesting("Betanet", network: .ecashBeta)
        WalletManager.setRemoteDisplayNameForTesting("eCash", network: .ecashMainnet)
        #expect(NetworkSelector.label(for: .ecashBeta) == "eCash Betanet (ECX)")
        #expect(NetworkSelector.label(for: .ecashMainnet) == "eCash (ECX)")

        WalletManager.setRemoteDisplayNameForTesting("eCash Betanet", network: .ecashBeta)
        #expect(NetworkSelector.label(for: .ecashBeta) == "eCash Betanet (ECX)")
        Self.reset()
    }
}
