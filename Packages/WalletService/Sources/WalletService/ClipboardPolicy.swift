// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

#if !SKIP_BRIDGE

import Foundation

/// How seed-equivalent text (user entropy, a WIF private key) is allowed to sit on the clipboard.
/// Addresses and txids are public and use the plain copy; this policy is only for text that can
/// derive the wallet. Pure, so the decisions are testable without a pasteboard.
///
/// On iOS the OS enforces the lifetime (`UIPasteboard` `expirationDate`) and keeps the text off
/// Universal Clipboard (`localOnly`). On Android there is no expiry API, so the app schedules its
/// own clear and asks `shouldClear` whether the clipboard still holds what it put there.
public enum ClipboardPolicy {
    /// How long a sensitive copy stays on the clipboard. Long enough to paste into a terminal for
    /// the entropy shasum check, short enough that it is gone before the user forgets it is there.
    public static let sensitiveLifetimeSeconds: Int64 = 60

    /// The Android clip label. The default copy says "address"; a seed must not be described as
    /// anything, so the label says nothing.
    public static let sensitiveLabel: String = ""

    /// Whether the scheduled clear should run. `current` is what the clipboard holds now, or nil
    /// when it is empty or the OS would not let the app read it (Android 10+ hides the clipboard
    /// from an app that is no longer in focus).
    ///
    /// - Still our text → clear it.
    /// - Unreadable or empty → clear anyway. An empty clipboard loses nothing, and an unreadable one
    ///   may still hold the seed; wiping something the user copied elsewhere in the meantime is an
    ///   annoyance, leaving a seed on the clipboard is not.
    /// - Something else the user copied since → leave it alone.
    public static func shouldClear(current: String?, copied: String) -> Bool {
        guard let current = current, !current.isEmpty else { return true }
        return current == copied
    }
}

#endif // !SKIP_BRIDGE — bridged module: bodies excluded from the bridge compile
