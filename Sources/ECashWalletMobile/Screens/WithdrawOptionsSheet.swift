// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WalletService

/// What "Withdraw" opens on a sidechain wallet: the two ways to move coins back to the mainchain, each
/// explained before the user picks — the slow, trustless regular withdrawal, and the fast withdrawal
/// through a liquidity provider (`docs/fast-withdrawal.md`). Fast withdrawals still in progress are
/// listed first so the user can get back to them.
///
/// Fast withdrawal is switched on/off in `FastWithdrawalConfig.isEnabled`; when off (or the sidechain
/// has no service) it shows as "Coming soon".
struct WithdrawOptionsSheet: View {
    @Environment(AppState.self) var app
    @Environment(\.dismiss) var dismiss   // not `private` — Fuse bridges view properties
    @State var path: [WithdrawRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.x4) {
                    Text("Move coins back to \(mainchainName).", bundle: .module,
                         comment: "withdraw options intro; %@ is the mainchain name")
                        .textStyle(.sm)
                        .foregroundStyle(Theme.Colors.text1)

                    ForEach(activeFast) { record in
                        option(icon: Icon.pending,
                               title: Text("Fast withdrawal in progress", bundle: .module,
                                           comment: "withdraw options: an unfinished fast withdrawal"),
                               body: Text(verbatim: "\(Amount(sats: record.l1PayoutSats).formattedCoin()) → \(record.l1Destination)"),
                               badge: nil, enabled: true) {
                            path.append(.fastTracking(record.id))
                        }
                    }

                    option(icon: Icon.pending,
                           title: Text("Regular withdrawal", bundle: .module, comment: "withdraw option title"),
                           body: Text("Miners approve it through the chain itself. No middleman and only network fees, but it takes months — about 3 at best.",
                                      bundle: .module, comment: "regular withdrawal explanation"),
                           badge: nil, enabled: true) {
                        path.append(.regular)
                    }

                    // ── Fast withdrawal option ───────────────────────────────────────────────────
                    // On/off: FastWithdrawalConfig.isEnabled. To remove the option entirely, comment out
                    // this one call.
                    option(icon: Icon.send,
                           title: Text("Fast withdrawal", bundle: .module, comment: "withdraw option title"),
                           body: Text("A liquidity provider pays you on \(mainchainName) right away and takes your coins in return, for a small fee. You rely on the provider.",
                                      bundle: .module, comment: "fast withdrawal explanation; %@ is the mainchain name"),
                           badge: fastAvailable ? nil
                               : Text("Coming soon", bundle: .module, comment: "fast withdrawal unavailable badge"),
                           enabled: fastAvailable) {
                        path.append(.fast)
                    }
                    // ─────────────────────────────────────────────────────────────────────────────
                }
                .padding(Theme.Space.gutter)
            }
            .scrollIndicators(.hidden)
            .background(Theme.Colors.bg0)
            .navigationTitle(Text("Withdraw", bundle: .module, comment: "withdraw options sheet title"))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseToolbarButton { dismiss() } }
            }
            .navigationDestination(for: WithdrawRoute.self) { route in
                switch route {
                case .regular:
                    if let vm = app.makeSidechainWithdrawViewModel() {
                        SidechainWithdrawScreen(viewModel: vm) { dismiss() }
                    }
                case .fast:
                    if let vm = app.makeFastWithdrawalViewModel() {
                        FastWithdrawalScreen(viewModel: vm) { dismiss() }
                    }
                case .fastTracking(let id):
                    if let record = activeFast.first(where: { $0.id == id }) ?? trackedRecord(id),
                       let vm = app.makeFastWithdrawalViewModel(resuming: record) {
                        FastWithdrawalScreen(viewModel: vm) { dismiss() }
                    }
                }
            }
        }
    }

    private var fastAvailable: Bool { app.fastWithdrawalEndpoint != nil }

    /// Read when the sheet appears (and each time it re-renders); nothing to show when the feature is off.
    private var activeFast: [FastWithdrawalRecord] {
        fastAvailable ? app.activeFastWithdrawals() : []
    }

    private func trackedRecord(_ id: String) -> FastWithdrawalRecord? {
        guard let walletId = app.selectedWalletId else { return nil }
        return app.fastWithdrawalStore.record(id: id, walletId: walletId)
    }

    private var mainchainName: String {
        guard let network = app.selectedWallet?.network,
              let mainchain = SidechainWalletNetwork.mainchain(ofSidechainWallet: network) else { return "" }
        return NetworkRegistry.params(for: mainchain).displayName
    }

    private func option(icon: Icon, title: Text, body: Text, badge: Text?, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Space.x3) {
                Image(icon: icon)
                    .resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(enabled ? Theme.Colors.accent : Theme.Colors.text2)
                VStack(alignment: .leading, spacing: Theme.Space.x1) {
                    HStack(spacing: Theme.Space.x2) {
                        title.textStyle(.h3).foregroundStyle(Theme.Colors.text0)
                        if let badge {
                            badge.textStyle(.xs)
                                .foregroundStyle(Theme.Colors.text1)
                                .padding(.horizontal, Theme.Space.x2)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.bg2, in: Capsule())
                        }
                    }
                    body.textStyle(.sm)
                        .foregroundStyle(Theme.Colors.text1)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if enabled {
                    Image(icon: Icon.disclosure)
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Theme.Colors.text2)
                }
            }
            .padding(Theme.Space.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Colors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
    }
}

enum WithdrawRoute: Hashable {
    case regular
    case fast
    case fastTracking(String)   // withdrawal id
}
