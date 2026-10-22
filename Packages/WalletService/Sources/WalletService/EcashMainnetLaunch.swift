// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

#if !SKIP_BRIDGE
import Foundation

/// When the real eCash mainnet (`WalletNetwork.ecashMainnet`) is **offered** and when it becomes the
/// **default** eCash network — both driven by the chain and the remote config, not by a release.
///
/// Two independent gates (both read from UserDefaults, written by the config-apply path):
///
/// 1. **Offered** — the remote config has delivered a backend for `.ecashMainnet` (the `ecash-mainnet`
///    entry on drivechain.dev/config). Until then the case is invisible: not in the create/import
///    picker, not a copy-wallet target. Shipping the case ahead of the fork is what lets the entry
///    turn the network on in every installed copy with no update.
/// 2. **Default** — offered AND the chain has been observed at or past the entry's `fork_height`
///    (`WalletManager.effectiveForkHeight`, i.e. the config's value with the compiled 973,728 as the
///    fallback). Before that block the "mainnet" chain is still Bitcoin; defaulting new wallets there
///    early would put them on a chain that doesn't exist yet. The app records the tip it observes via
///    `recordObservedTip` and the result latches: a fork does not un-happen.
///
/// Betanet is untouched by either gate — it stays offered, and stays the default until the fork.
public enum EcashMainnetLaunch {
    private static let forkReachedKey = "ecashMainnet.forkReached"

    /// The remote config has published an endpoint for eCash mainnet.
    public static var isOffered: Bool {
        WalletManager.hasRemoteBackendDefault(for: .ecashMainnet)
    }

    /// Offered, and the chain has been seen past the mainnet fork height.
    public static var isDefault: Bool {
        isOffered && UserDefaults.standard.bool(forKey: forkReachedKey)
    }

    /// The fork height the default gate compares against: the config's `fork_height` for the mainnet
    /// entry if one has been applied, else the compiled value.
    public static var forkHeight: Int64 {
        WalletManager.effectiveForkHeight(for: .ecashMainnet) ?? Int64(973_728)
    }

    /// Record a chain tip observed on the mainnet (or, pre-fork, the Bitcoin) chain. Latches the
    /// default gate once the tip reaches the fork height. Returns true if this call flipped it.
    @discardableResult
    public static func recordObservedTip(height: Int64) -> Bool {
        guard height >= forkHeight else { return false }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: forkReachedKey) else { return false }
        defaults.set(true, forKey: forkReachedKey)
        return true
    }

    /// Test seam: clear the latch (and, with `offered`, store or remove a fake remote backend).
    public static func resetForTesting(offered: Bool) {
        UserDefaults.standard.removeObject(forKey: forkReachedKey)
        WalletManager.setRemoteBackendDefaultForTesting(offered ? "https://esplora.mainnet.example" : nil,
                                                        kind: "esplora", network: .ecashMainnet)
    }
}
#endif // !SKIP_BRIDGE — bridged module: bodies excluded from the bridge compile
