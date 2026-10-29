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
/// 1. **Offered** — compiled on since 1.4.6 build 44 (`offeredInThisBuild`), OR the remote config has
///    delivered a backend for `.ecashMainnet` (the `ecash` entry on drivechain.dev/config, published
///    2026-10-26). The remote half is what turned the network on in builds 41–43 with no update;
///    from build 44 the picker no longer waits on a fetch.
/// 2. **Fork seen** (`isDefault`, historically "default") — offered AND the chain has been observed
///    at or past the entry's `fork_height` (`WalletManager.effectiveForkHeight`, i.e. the config's
///    value with the compiled 973,728 as the fallback). The app records the tip it observes via
///    `recordObservedTip` and the result latches: a fork does not un-happen. **Since 1.4.6 build 44
///    (2026-10-29) this no longer steers `WalletNetwork.currentEcash`**, which is the real fork
///    unconditionally (Jake); the latch is kept as the app's record that the fork has happened.
///
/// Betanet is untouched by either gate — it stays offered, second in the picker.
public enum EcashMainnetLaunch {
    private static let forkReachedKey = "ecashMainnet.forkReached"

    /// **Offered in this build regardless of the config** (2026-10-29). drivechain.dev/config
    /// published the `ecash` entry on 2026-10-26 and the fork is hours away, so gating the picker
    /// on a successful fetch only cost users the network: a launch whose first fetch failed or was
    /// throttled showed no eCash mainnet until a later resume (reported on Android 1.4.6). The
    /// remote gate below stays for the build 41–43 installs that still need it; here it is redundant.
    public static let offeredInThisBuild = true

    /// Offered: compiled in (above), or the remote config has published an endpoint for it.
    public static var isOffered: Bool {
        offeredInThisBuild || WalletManager.hasRemoteBackendDefault(for: .ecashMainnet)
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
