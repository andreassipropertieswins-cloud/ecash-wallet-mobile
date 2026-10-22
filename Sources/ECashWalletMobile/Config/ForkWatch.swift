// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import WalletService

/// Watches for the real eCash fork, so eCash mainnet becomes the default eCash network the moment the
/// chain is past its fork height — with no release and no config change (`EcashMainnetLaunch`).
///
/// Only runs once the config has turned mainnet on (`isOffered`) and until the fork is seen
/// (`isDefault`), so it costs nothing before and after. It asks an Esplora for `/blocks/tip/height`
/// (a bare integer; mempool-electrs serves it at the root path): the mainnet entry's own Esplora
/// first, then Bitcoin's — pre-fork they are the same chain, and post-fork both are past the height.
/// Betanet's tip is never consulted: betanet mines its own blocks and is already past 973,728.
///
/// A result below the height, a network error or a malformed body all mean "not yet"; nothing is
/// written. The latch is one-way (`recordObservedTip`): a fork does not un-happen.
enum ForkWatch {
    /// The Esplora bases to ask, in order. Only remotely-configured ones: a bundled guess could
    /// not be trusted to describe the right chain.
    static func candidateBases() -> [String] {
        var out: [String] = []
        if let mainnet = RemoteServiceOverrides.esploraURL(for: .ecashMainnet) { out.append(mainnet) }
        if let bitcoin = RemoteServiceOverrides.esploraURL(for: .bitcoin) { out.append(bitcoin) }
        return out
    }

    /// Parse an Esplora `/blocks/tip/height` body.
    static func parseTip(_ data: Data) -> Int64? {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let height = Int64(text), height > 0 else { return nil }
        return height
    }

    /// The tip reported by the first base that answers, or nil if none does.
    static func observedTip(bases: [String], fetch: DashboardFetch) async -> Int64? {
        for base in bases {
            guard let url = try? DashboardHTTP.url(base, "/blocks/tip/height"),
                  let data = try? await DashboardHTTP.get(url, using: fetch),
                  let height = parseTip(data) else { continue }
            return height
        }
        return nil
    }

    /// Check the chain if the gate is armed. Returns true if this call made mainnet the default.
    @discardableResult
    static func checkIfNeeded(fetch: @escaping DashboardFetch = DashboardHTTP.live) async -> Bool {
        guard EcashMainnetLaunch.isOffered, !EcashMainnetLaunch.isDefault else { return false }
        guard let tip = await observedTip(bases: candidateBases(), fetch: fetch) else { return false }
        return EcashMainnetLaunch.recordObservedTip(height: tip)
    }
}
