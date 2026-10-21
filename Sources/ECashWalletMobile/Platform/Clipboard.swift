// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import WalletService
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#endif

/// Cross-platform "copy text to the system clipboard". SwiftUI has no portable clipboard API, so
/// this bridges per platform: `UIPasteboard` on iOS; on Android we delegate to the transpiled
/// WalletService (`Platform.copyToClipboard`), which does the Kotlin `ClipboardManager` call —
/// reliable, unlike calling Android APIs from this Fuse module's native Swift via AnyDynamicObject.
enum Clipboard {
    /// Copy PUBLIC text — addresses, txids, payment links. Ordinary clipboard semantics: it syncs
    /// to the user's other devices and stays until overwritten. Never pass seed-equivalent text
    /// here; that is what `copySensitive` is for.
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(Android)
        PlatformBridge.copyToClipboard(text)
        #endif
    }

    /// Copy SEED-EQUIVALENT text — user entropy, a WIF private key — anything that can derive the
    /// wallet. The copy exists because a 100+ character entropy string can only be audited by
    /// pasting it, but it must not linger: it leaves the clipboard after
    /// `ClipboardPolicy.sensitiveLifetimeSeconds` and never leaves the device.
    ///
    /// - iOS: `localOnly` keeps it off Universal Clipboard (and so off iCloud); `expirationDate`
    ///   has the OS clear it.
    /// - Android: `PlatformBridge` flags it sensitive (hidden from the Android 13+ overlay and
    ///   keyboard suggestions) and schedules the clear itself.
    static func copySensitive(_ text: String) {
        #if os(iOS)
        let expiry = Date().addingTimeInterval(TimeInterval(ClipboardPolicy.sensitiveLifetimeSeconds))
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: expiry])
        #elseif os(Android)
        PlatformBridge.copySensitiveToClipboard(text)
        #endif
    }

    /// Read plain text from the clipboard, or nil when there's nothing usable there.
    ///
    /// Note for iOS: reading `UIPasteboard` programmatically makes the system show its "Allow
    /// Paste?" prompt (iOS 16+) unless the user has already allowed it for this app. That's the OS
    /// protecting clipboard contents and there's no way around it short of `PasteButton`, which
    /// SkipUI doesn't provide — so we accept the prompt rather than lose the feature on Android.
    static func paste() -> String? {
        #if os(iOS)
        let text = UIPasteboard.general.string
        guard let text, !text.isEmpty else { return nil }
        return text
        #elseif os(Android)
        return PlatformBridge.pasteFromClipboard()
        #else
        return nil
        #endif
    }
}
