// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// One fast withdrawal as this app remembers it. Written **before** the Thunder payment is broadcast,
/// so a withdrawal is never paid without a handle on it (`docs/fast-withdrawal.md` §7).
struct FastWithdrawalRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String              // withdrawal_id
    let walletId: String
    let requestID: String
    let sidechain: String
    let l1Destination: String
    let l1PayoutSats: Int64
    let l2PaymentAddress: String
    let l2PaymentSats: Int64
    let serviceFeeSats: Int64
    let expiresAt: Int64
    let createdAt: Int64
    /// Set the moment our payment is broadcast. Nil with `paymentStarted` true means the app stopped
    /// mid-payment: the service finds the payment on its own once mined, so polling resolves it, and
    /// the app must NOT pay again.
    var paymentTxid: String?
    var paymentStarted: Bool
    var status: FastWithdrawalStatus
    var payoutTxid: String?
    var l2ReceivedSats: Int64
    var l2RefundAddress: String?
    /// The user closed a finished withdrawal's progress view; it no longer appears as active.
    var dismissed: Bool

    /// Still worth showing and polling: paid (or being paid) and not settled.
    var isActive: Bool { !dismissed && paymentStarted && !status.isFinal }

    mutating func apply(_ remote: FastWithdrawal) {
        status = remote.status
        if !remote.payoutTxid.isEmpty { payoutTxid = remote.payoutTxid }
        if !remote.paymentTxid.isEmpty, paymentTxid == nil { paymentTxid = remote.paymentTxid }
        if remote.l2ReceivedSats > 0 { l2ReceivedSats = remote.l2ReceivedSats }
        if !remote.l2RefundAddress.isEmpty { l2RefundAddress = remote.l2RefundAddress }
    }
}

/// Per-wallet persistence (Golden Rule §5: keyed by `walletId`, purged on removal). A JSON string in
/// UserDefaults, like `SplitCheckStore` — `UserDefaults.dictionary(forKey:)` isn't in Skip's Foundation.
/// Holds public data only: amounts, addresses and txids, never key material.
struct FastWithdrawalStore {
    private static let key = "fastwithdraw.records.v1"
    var defaults: UserDefaults = .standard

    private var all: [String: [FastWithdrawalRecord]] {
        get {
            guard let raw = defaults.string(forKey: Self.key), let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: [FastWithdrawalRecord]].self, from: data)
            else { return [:] }
            return decoded
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let raw = String(data: data, encoding: .utf8) else { return }
            defaults.set(raw, forKey: Self.key)
        }
    }

    /// Newest first.
    func records(walletId: String) -> [FastWithdrawalRecord] {
        (all[walletId] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func activeRecords(walletId: String) -> [FastWithdrawalRecord] {
        records(walletId: walletId).filter { $0.isActive }
    }

    func record(id: String, walletId: String) -> FastWithdrawalRecord? {
        all[walletId]?.first { $0.id == id }
    }

    /// Insert or replace by withdrawal id.
    func save(_ record: FastWithdrawalRecord) {
        var everything = all
        var list = everything[record.walletId] ?? []
        if let i = list.firstIndex(where: { $0.id == record.id }) { list[i] = record } else { list.append(record) }
        everything[record.walletId] = list
        all = everything
    }

    /// Purge on wallet removal.
    func forget(walletId: String) {
        var everything = all
        everything.removeValue(forKey: walletId)
        all = everything
    }
}
