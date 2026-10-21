// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import WalletService
import SkipQRCode   // Android camera scanner (AndroidBarcodeScanner); iOS uses QRScannerView, as Send does

/// Fast withdrawal through a liquidity provider: destination + amount, then a verified quote to
/// review (with the trust stated plainly), device auth, payment, and progress until paid out.
/// Pushed from `WithdrawOptionsSheet`, which also reopens withdrawals still in progress.
struct FastWithdrawalScreen: View {
    @State var vm: FastWithdrawalViewModel
    @State var showScanner = false
    @State var showDestinations = false
    let onFinish: () -> Void

    init(viewModel: FastWithdrawalViewModel, onFinish: @escaping () -> Void) {
        _vm = State(initialValue: viewModel)
        self.onFinish = onFinish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.x5) {
                switch vm.phase {
                case .loading:
                    working(Text("Contacting the provider…", bundle: .module, comment: "fast withdrawal loading"))
                case .unavailable(let message):
                    problem(message, retryTitle: "Try again") { Task { await vm.retryLoading() } }
                case .entering:
                    entering
                case .quoting:
                    working(Text("Getting a quote…", bundle: .module, comment: "fast withdrawal quote in progress"))
                case .reviewing(let quote):
                    review(quote)
                case .paying:
                    working(Text("Paying on \(vm.sidechainTitle)…", bundle: .module,
                                 comment: "fast withdrawal payment in progress; %@ is the sidechain"))
                case .tracking:
                    tracking
                case .failed(let message):
                    problem(message, retryTitle: "Edit") { vm.back() }
                }
            }
            .padding(Theme.Space.gutter)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Colors.bg0)
        .navigationTitle(Text("Fast withdrawal", bundle: .module, comment: "fast withdrawal screen title"))
        .inlineNavigationTitle()
        // Never let Back interrupt a payment in flight.
        .navigationBarBackButtonHidden(vm.isBusy || vm.phase == .paying)
        .task { await vm.loadIfNeeded() }
        .task(id: vm.phase == .tracking) {
            if vm.phase == .tracking { await vm.track() }
        }
        .sheet(isPresented: $showDestinations) {
            SendDestinationPicker(destinations: vm.destinations,
                                  networkDisplayName: vm.mainchainDisplayName,
                                  unitLabel: NetworkRegistry.params(for: vm.mainchain).unitLabel) { destination in
                Task { await vm.useDestination(destination) }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showScanner) {
            ZStack(alignment: .topTrailing) {
                QRScannerView { code in
                    vm.addressText = code
                    showScanner = false
                }
                .ignoresSafeArea()

                Button { showScanner = false } label: {
                    Image(icon: Icon.close)
                        .resizable().scaledToFit().frame(width: 20, height: 20)
                        .foregroundStyle(.white)
                        .padding(Theme.Space.x3)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .padding(Theme.Space.x4)
            }
        }
        #endif
    }

    private func startScan() {
        #if os(iOS)
        showScanner = true
        #else
        AndroidBarcodeScanner.scan { code in
            guard let code else { return }
            Task { @MainActor in vm.addressText = code }
        }
        #endif
    }

    // MARK: - Entering

    @ViewBuilder private var entering: some View {
        header

        fieldLabel(Text("To", bundle: .module, comment: "withdrawal destination label"))
        HStack(spacing: Theme.Space.x2) {
            TextField("\(vm.mainchainDisplayName) address", text: $vm.addressText)
                .textFieldStyle(.plain)
                .font(.jbMono(14, .regular))
                .foregroundStyle(Theme.Colors.text0)
                .autocorrectionDisabled()
                .noAutocapitalization()
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let pasted = Clipboard.paste() {
                    vm.addressText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Text("Paste", bundle: .module, comment: "send: paste an address from the clipboard")
                    .textStyle(.sm)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)

            Button { startScan() } label: {
                Image(icon: Icon.scan)
                    .resizable().scaledToFit().frame(width: 20, height: 20)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .fieldBoxInset()
        .background(Theme.Colors.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.md))

        if vm.hasDestinations {
            Button { showDestinations = true } label: {
                HStack(spacing: Theme.Space.x2) {
                    Image(icon: Icon.wallet)
                        .resizable().scaledToFit().frame(width: 16, height: 16)
                    Text("Withdraw to one of my \(vm.mainchainDisplayName) wallets", bundle: .module,
                         comment: "withdrawal: pick one of the user's mainchain wallets; %@ is the mainchain name")
                        .textStyle(.sm)
                    if vm.isResolvingDestination {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(vm.isResolvingDestination)
        }

        if let destinationError = vm.destinationError {
            note(Text(verbatim: destinationError), negative: true)
        }
        if vm.addressText.isEmpty {
            note(Text("Only a \(vm.mainchainDisplayName) address. Coins sent to any other chain's address are lost.",
                      bundle: .module, comment: "withdrawal address hint; %@ is the mainchain name"), negative: false)
        } else if vm.isAddressInvalid {
            note(Text("Not a valid \(vm.mainchainDisplayName) address", bundle: .module,
                      comment: "withdrawal address invalid for the mainchain; %@ is the mainchain name"), negative: true)
        }

        fieldLabel(Text("You receive", bundle: .module, comment: "fast withdrawal payout amount label"))
        HStack(spacing: Theme.Space.x2) {
            TextField("0.00000000", text: $vm.amountText)
                .textFieldStyle(.plain)
                .textStyle(.mono)
                .foregroundStyle(Theme.Colors.text0)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .fieldBoxInset()
                .background(Theme.Colors.bg2, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            Text(verbatim: vm.unitLabel)
                .textStyle(.sm)
                .foregroundStyle(Theme.Colors.text2)
        }
        amountNote

        WalletButton(title: "Get quote") { Task { await vm.requestQuote() } }
            .disabled(!vm.canQuote)
            .opacity(vm.canQuote ? 1 : 0.4)
    }

    @ViewBuilder private var amountNote: some View {
        let min = vm.minimum?.formattedCoin() ?? ""
        let max = vm.maximum?.formattedCoin() ?? ""
        switch vm.amountProblem {
        case .belowMinimum:
            note(Text("The minimum is \(min) \(vm.unitLabel).", bundle: .module,
                      comment: "fast withdrawal below minimum; %1$@ amount, %2$@ unit"), negative: true)
        case .aboveMaximum:
            note(Text("The maximum is \(max) \(vm.unitLabel).", bundle: .module,
                      comment: "fast withdrawal above maximum; %1$@ amount, %2$@ unit"), negative: true)
        case .exceedsBalance:
            note(Text("That plus the provider's fee is more than this wallet can spend.", bundle: .module,
                      comment: "fast withdrawal amount + fee too large"), negative: true)
        case .none:
            if let fee = vm.estimatedFee {
                note(Text("Provider fee about \(fee.formattedCoin()) \(vm.unitLabel) (\(vm.feePercentText)), plus a small \(vm.sidechainTitle) network fee. Available: \(vm.spendable.formattedCoin()) \(vm.unitLabel).",
                          bundle: .module, comment: "fast withdrawal fee estimate; %1$@ fee, %2$@ unit, %3$@ percent, %4$@ sidechain, %5$@ balance, %6$@ unit"),
                     negative: false)
            } else {
                note(Text("Between \(min) and \(max) \(vm.unitLabel). Provider fee \(vm.feePercentText). Available: \(vm.spendable.formattedCoin()) \(vm.unitLabel).",
                          bundle: .module, comment: "fast withdrawal limits; %1$@ min, %2$@ max, %3$@ unit, %4$@ percent, %5$@ balance, %6$@ unit"),
                     negative: false)
            }
        }
    }

    /// From → to, as the two network chips. No card and no kind label: the title already says which
    /// withdrawal this is, and squeezing a label in beside the chips made the sidechain's wrap.
    private var header: some View {
        HStack(spacing: Theme.Space.x2) {
            NetworkBadge(network: vm.sidechainNetwork)
            Image(icon: Icon.disclosure)
                .resizable().scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(Theme.Colors.text2)
            NetworkBadge(network: vm.mainchain)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Review (Golden Rule §7: network, recipient, amount, fee — and who is trusted)

    @ViewBuilder private func review(_ quote: FastWithdrawal) -> some View {
        header

        VStack(alignment: .leading, spacing: Theme.Space.x3) {
            reviewRow(Text("You pay on \(vm.sidechainTitle)", bundle: .module,
                           comment: "fast withdrawal review: amount paid; %@ sidechain"),
                      Text(verbatim: "\(Amount(sats: quote.l2PaymentSats).formattedCoin()) \(vm.unitLabel)"))
            hairline
            reviewRow(Text("You receive on \(vm.mainchainDisplayName)", bundle: .module,
                           comment: "fast withdrawal review: payout; %@ mainchain"),
                      Text(verbatim: "\(Amount(sats: quote.l1PayoutSats).formattedCoin()) \(vm.unitLabel)"))
            hairline
            reviewRow(Text("Provider fee", bundle: .module, comment: "fast withdrawal review row"),
                      Text(verbatim: "\(Amount(sats: quote.serviceFeeSats).formattedCoin()) \(vm.unitLabel)"))
            hairline
            reviewRow(Text("\(vm.sidechainTitle) network fee", bundle: .module,
                           comment: "fast withdrawal review: sidechain tx fee; %@ sidechain"),
                      Text("A few sats", bundle: .module, comment: "fast withdrawal review: small sidechain fee"))
            hairline
            VStack(alignment: .leading, spacing: Theme.Space.x1) {
                Text("To", bundle: .module, comment: "withdrawal destination label")
                    .textStyle(.sm)
                    .foregroundStyle(Theme.Colors.text2)
                Text(verbatim: quote.l1Destination)
                    .font(.jbMono(13, .regular))
                    .foregroundStyle(Theme.Colors.text0)
            }
            hairline
            reviewRow(Text("Quote expires", bundle: .module, comment: "fast withdrawal review row"),
                      Text("in \(String(max(1, (vm.secondsLeft ?? 0) / 60))) min", bundle: .module,
                           comment: "fast withdrawal quote expiry; %@ minutes"))
        }
        .card()

        trustWarning

        Toggle(isOn: $vm.acknowledged) {
            Text("I understand I'm trusting \(vm.operatorName) to pay me, and that a payment can't be reversed.",
                 bundle: .module, comment: "fast withdrawal acknowledgement; %@ operator name")
                .textStyle(.sm)
                .foregroundStyle(Theme.Colors.text0)
        }
        .tint(Theme.Colors.accent)

        WalletButton(title: "Pay and withdraw") { Task { await vm.confirm() } }
            .disabled(!vm.canConfirm)
            .opacity(vm.canConfirm ? 1 : 0.4)
        WalletButton(title: "Edit", kind: .secondary) { vm.back() }
            .disabled(vm.isBusy)
    }

    private var trustWarning: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x2) {
            Text("You're trusting \(vm.operatorName).", bundle: .module,
                 comment: "fast withdrawal trust warning title; %@ operator")
                .textStyle(.h3)
                .foregroundStyle(Theme.Colors.text0)
            Text("You pay \(vm.operatorName) on \(vm.sidechainTitle) first. They then pay you on \(vm.mainchainDisplayName), usually within minutes of your payment confirming. If they don't, there's no way to get the coins back on-chain.",
                 bundle: .module, comment: "fast withdrawal trust explanation; %1$@ operator, %2$@ sidechain, %3$@ mainchain, %4$@ operator")
                .textStyle(.sm)
                .foregroundStyle(Theme.Colors.text0)
            Text("The quote was signed by the provider and checked by this app before you can pay.",
                 bundle: .module, comment: "fast withdrawal: quote verified note")
                .textStyle(.xs)
                .foregroundStyle(Theme.Colors.text1)
        }
        .padding(Theme.Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.warningTint, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Colors.warning.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Tracking

    @ViewBuilder private var tracking: some View {
        if let record = vm.record {
            header

            VStack(alignment: .leading, spacing: Theme.Space.x3) {
                HStack(spacing: Theme.Space.x2) {
                    if !record.status.isFinal { ProgressView().scaleEffect(0.8) }
                    statusTitle(record.status)
                        .textStyle(.h3)
                        .foregroundStyle(record.status == .paid ? Theme.Colors.positive
                                         : record.status == .failed ? Theme.Colors.negative : Theme.Colors.text0)
                }
                statusBody(record)
                    .textStyle(.sm)
                    .foregroundStyle(Theme.Colors.text1)
            }
            .card()

            if let notice = vm.paymentNotice {
                note(Text(verbatim: notice), negative: true)
            }

            VStack(alignment: .leading, spacing: Theme.Space.x3) {
                reviewRow(Text("Paid", bundle: .module, comment: "fast withdrawal progress row"),
                          Text(verbatim: "\(Amount(sats: record.l2PaymentSats).formattedCoin()) \(vm.unitLabel)"))
                hairline
                reviewRow(Text("Receiving", bundle: .module, comment: "fast withdrawal progress row"),
                          Text(verbatim: "\(Amount(sats: record.l1PayoutSats).formattedCoin()) \(vm.unitLabel)"))
                if let txid = record.paymentTxid {
                    hairline
                    txidRow(Text("\(vm.sidechainTitle) payment", bundle: .module,
                                 comment: "fast withdrawal: sidechain payment txid; %@ sidechain"), txid)
                }
                if let payout = record.payoutTxid {
                    hairline
                    txidRow(Text("\(vm.mainchainDisplayName) payout", bundle: .module,
                                 comment: "fast withdrawal: mainchain payout txid; %@ mainchain"), payout)
                }
                hairline
                txidRow(Text("Withdrawal ID", bundle: .module, comment: "fast withdrawal id row"), record.id)
            }
            .card()

            if record.status == .underpaid, record.l2RefundAddress == nil {
                WalletButton(title: vm.isRequestingRefund ? "Requesting…" : "Request a refund") {
                    Task { await vm.requestRefund() }
                }
                .disabled(vm.isRequestingRefund)
                if let error = vm.refundError { note(Text(verbatim: error), negative: true) }
            }

            if record.status.isFinal {
                WalletButton(title: "Done") {
                    vm.dismiss()
                    onFinish()
                }
            } else {
                note(Text("You can leave this screen. The withdrawal carries on, and you can check it again from Withdraw.",
                          bundle: .module, comment: "fast withdrawal: safe to leave"), negative: false)
            }
        }
    }

    private func statusTitle(_ status: FastWithdrawalStatus) -> Text {
        switch status {
        case .unspecified, .awaitingPayment, .expired:
            return Text("Waiting for your payment", bundle: .module, comment: "fast withdrawal status")
        case .confirmingPayment:
            return Text("Confirming your payment", bundle: .module, comment: "fast withdrawal status")
        case .paymentConfirmed, .payoutPrepared:
            return Text("Paying you out", bundle: .module, comment: "fast withdrawal status")
        case .paid:
            return Text("Paid", bundle: .module, comment: "fast withdrawal status")
        case .failed:
            return Text("Payout failed", bundle: .module, comment: "fast withdrawal status")
        case .underpaid:
            return Text("Payment too small", bundle: .module, comment: "fast withdrawal status")
        case .refunded:
            return Text("Refunded", bundle: .module, comment: "fast withdrawal status")
        }
    }

    private func statusBody(_ record: FastWithdrawalRecord) -> Text {
        switch record.status {
        case .unspecified, .awaitingPayment, .expired:
            return Text("The provider hasn't seen your \(vm.sidechainTitle) payment yet. It will once it's in a block.",
                        bundle: .module, comment: "fast withdrawal status body; %@ sidechain")
        case .confirmingPayment:
            return Text("Your payment needs a couple of \(vm.sidechainTitle) confirmations before the provider pays out.",
                        bundle: .module, comment: "fast withdrawal status body; %@ sidechain")
        case .paymentConfirmed, .payoutPrepared:
            return Text("Your payment is confirmed. The provider is sending your coins on \(vm.mainchainDisplayName).",
                        bundle: .module, comment: "fast withdrawal status body; %@ mainchain")
        case .paid:
            return Text("Your coins were sent on \(vm.mainchainDisplayName). They'll show in that wallet once it syncs.",
                        bundle: .module, comment: "fast withdrawal status body; %@ mainchain")
        case .failed:
            return Text("The provider couldn't pay this out. Contact \(vm.operatorName) with the withdrawal ID below.",
                        bundle: .module, comment: "fast withdrawal status body; %@ operator")
        case .underpaid:
            return Text("The provider received \(Amount(sats: record.l2ReceivedSats).formattedCoin()) \(vm.unitLabel), less than the quote, so it won't pay out. You can ask for it back.",
                        bundle: .module, comment: "fast withdrawal underpaid; %1$@ amount, %2$@ unit")
        case .refunded:
            return Text("Your payment was sent back to this wallet, less a network fee.",
                        bundle: .module, comment: "fast withdrawal refunded")
        }
    }

    // MARK: - Pieces

    private func working(_ label: Text) -> some View {
        VStack(spacing: Theme.Space.x3) {
            ProgressView()
            label.textStyle(.sm).foregroundStyle(Theme.Colors.text1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.x10)
    }

    @ViewBuilder private func problem(_ message: String, retryTitle: LocalizedStringKey,
                                      retry: @escaping () -> Void) -> some View {
        VStack(spacing: Theme.Space.x3) {
            Image(icon: Icon.caution)
                .resizable().scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Theme.Colors.negative)
            Text(verbatim: message)
                .textStyle(.sm)
                .foregroundStyle(Theme.Colors.text0)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.x8)

        WalletButton(title: retryTitle) { retry() }
    }

    private func txidRow(_ label: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.x1) {
            label.textStyle(.sm).foregroundStyle(Theme.Colors.text2)
            Button { Clipboard.copy(value) } label: {
                Text(verbatim: value)
                    .font(.jbMono(12, .regular))
                    .foregroundStyle(Theme.Colors.text0)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    private func note(_ text: Text, negative: Bool) -> some View {
        text
            .textStyle(.xs)
            .foregroundStyle(negative ? Theme.Colors.negative : Theme.Colors.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldLabel(_ text: Text) -> some View {
        text.textStyle(.overline).foregroundStyle(Theme.Colors.text1)
    }

    private func reviewRow(_ label: Text, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.x3) {
            label.textStyle(.sm).foregroundStyle(Theme.Colors.text2)
            Spacer(minLength: Theme.Space.x4)
            value.font(.jbMono(13, .regular)).foregroundStyle(Theme.Colors.text0).multilineTextAlignment(.trailing)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Theme.Colors.border).frame(height: 1)
    }
}

private extension View {
    func card() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.x4)
            .background(Theme.Colors.bg1, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Colors.border, lineWidth: 1))
    }
}
