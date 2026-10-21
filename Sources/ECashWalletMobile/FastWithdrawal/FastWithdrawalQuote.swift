// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Crypto   // swift-crypto: Ed25519 on iOS (CryptoKit) and Android (BoringSSL)

/// Checks a quote before anything is paid (`docs/fast-withdrawal.md` §4). Every failure here happens
/// before money moves, so the flow simply stops.
enum FastWithdrawalQuote {

    enum Problem: Error, Equatable {
        /// The signature doesn't verify against the service's key.
        case badSignature
        /// The service's key isn't the one this app was configured to expect.
        case unexpectedKey
        /// The quote isn't for what the user asked: destination, payout, or sidechain differ.
        case mismatch
        /// The amounts don't add up (payment ≠ payout + fee) or the fee is beyond the advertised rate.
        case badAmounts
        /// Expired, or too close to expiry to pay safely.
        case expiring
        /// Not waiting for a payment, or has no address to pay.
        case notPayable
    }

    /// Leave at least this long before expiry to get the payment into the mempool.
    static let minimumSecondsLeft: Int64 = 120

    /// The exact bytes the service signs: ten fields, each preceded by its 8-byte big-endian length.
    static func signedMessage(_ quote: FastWithdrawal) -> [UInt8] {
        var out: [UInt8] = []
        func part(_ bytes: [UInt8]) {
            out += bigEndian(Int64(bytes.count))
            out += bytes
        }
        part(Array("fastwithdraw.quote.v1".utf8) + [0])
        part(Array(quote.id.utf8))
        part(Array(quote.sidechain.utf8))
        part(Array(quote.l2PaymentAddress.utf8))
        part(bigEndian(quote.l2PaymentSats))
        part(Array(quote.l1Destination.utf8))
        part(bigEndian(quote.l1PayoutSats))
        part(bigEndian(quote.serviceFeeSats))
        part(bigEndian(quote.requiredConfirmations))
        part(bigEndian(quote.expiresAt))
        return out
    }

    static func signatureIsValid(_ quote: FastWithdrawal, publicKey: [UInt8]) -> Bool {
        guard publicKey.count == 32, quote.quoteSignature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(Data(quote.quoteSignature), for: Data(signedMessage(quote)))
    }

    /// Everything that must hold before paying. `pinnedKey` (from `FastWithdrawalConfig`) wins over
    /// the key the service reports, when set.
    static func check(_ quote: FastWithdrawal, info: FastWithdrawalServiceInfo, pinnedKey: [UInt8]?,
                      sidechain: String, l1Destination: String, l1PayoutSats: Int64,
                      nowSeconds: Int64) throws {
        if let pinnedKey, pinnedKey != info.quoteSigningPublicKey { throw Problem.unexpectedKey }
        guard signatureIsValid(quote, publicKey: pinnedKey ?? info.quoteSigningPublicKey) else {
            throw Problem.badSignature
        }
        guard quote.sidechain == sidechain, quote.l1Destination == l1Destination,
              quote.l1PayoutSats == l1PayoutSats else { throw Problem.mismatch }
        let total = quote.l1PayoutSats.addingReportingOverflow(quote.serviceFeeSats)
        guard quote.l1PayoutSats > 0, quote.serviceFeeSats >= 0, !total.overflow,
              quote.l2PaymentSats == total.partialValue,
              quote.serviceFeeSats <= info.estimatedFee(forPayout: quote.l1PayoutSats) else { throw Problem.badAmounts }
        guard quote.status == .awaitingPayment, !quote.l2PaymentAddress.isEmpty else { throw Problem.notPayable }
        guard quote.expiresAt - nowSeconds >= minimumSecondsLeft else { throw Problem.expiring }
    }

    private static func bigEndian(_ value: Int64) -> [UInt8] {
        let v = UInt64(bitPattern: value)
        return (0..<8).map { UInt8(truncatingIfNeeded: v >> (56 - 8 * UInt64($0))) }
    }
}
