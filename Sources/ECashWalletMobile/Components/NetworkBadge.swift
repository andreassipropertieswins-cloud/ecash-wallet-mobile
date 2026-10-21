// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WalletService

/// The persistent network-identity chip — a safety primitive, not decoration (Golden Rule §6): a
/// wallet's network must be unmistakable on every money-touching surface (home, send review,
/// receive, history, wallet switcher).
///
/// **Every** network shows a chip, each in its own color (`NetworkChipStyle`, a code-level config) —
/// testnets in high-contrast violet, **Bitcoin mainnet in its real orange**. The name + colors
/// resolve from the `WalletNetwork` (name via `NetworkRegistry`).
struct NetworkBadge: View {
    private let name: String
    private let style: NetworkChipStyle

    init(network: WalletNetwork) {
        self.name = NetworkRegistry.params(for: network).displayName
        self.style = NetworkChipStyle.style(for: network)
    }

    var body: some View {
        Text(verbatim: name)   // network display name (proper noun, from NetworkRegistry)
            .textStyle(.overline) // uppercased + tracked
            .lineLimit(1)
            .fixedSize()          // a chip never wraps onto two lines; its row makes room instead
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Theme.Space.x3)
            .padding(.vertical, Theme.Space.x1)
            .background(style.background, in: Capsule())
            .accessibilityLabel(Text("\(name) network",
                                     bundle: .module,
                                     comment: "Network badge accessibility label"))
    }
}
