// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import WalletService

/// Which eCash chain an investor claim ("Claim your ECX") lands on. Decided 2026-10-29 (Jake): the
/// claim follows the **selected wallet's** eCash chain — on a betanet wallet it claims on betanet, on
/// a mainnet wallet it claims on mainnet. Anything else selected (Bitcoin, Signet, Thunder, the
/// retired alphanet, or no wallet) claims on the real chain, which is what the investor letters are
/// for.
///
/// Deliberately NOT `WalletNetwork.currentEcash`: that stays betanet until the chain is seen past
/// the fork, which would have sent a claim made in the hours before block 973,728 to betanet even
/// from a mainnet wallet. An investor key holds the same pre-fork UTXOs on every eCash fork, so it
/// resolves on whichever chain this picks; pre-fork, a mainnet send is non-final (the compiled replay
/// nLockTime) and fails loud rather than moving coins.
enum ClaimNetwork {
    static func target(selected: WalletNetwork?) -> WalletNetwork {
        switch selected {
        case .ecashBeta: return .ecashBeta
        case .ecashMainnet: return .ecashMainnet
        default: return .ecashMainnet
        }
    }
}
