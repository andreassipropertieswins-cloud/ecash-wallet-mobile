// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Testing
import WalletService
@testable import ECashWalletMobile

/// The real eCash fork arrives through the remote config, beside betanet, under the id L2L's catalog
/// stages it as (`ecash-mainnet`; drivechain-frontends `netcatalog/testdata/ecash-mainnet.json`).
/// These check that the entry reaches `.ecashMainnet` and nothing else, that betanet is untouched,
/// and that the fork watcher flips the default only on a tip at or past the entry's fork height.
@Suite(.serialized) struct EcashMainnetConfigTests {

    /// L2L's staged fixture, trimmed to what matters. Mainnet FIRST, as they order it.
    private static let staged = """
    {
      "schema_version": 1,
      "networks": [
        { "id": "bitcoin", "family": "bitcoin", "display_name": "Bitcoin",
          "backends": [ { "kind": "esplora", "url": "https://esplora.mainnet.drivechain.info" } ] },
        { "id": "ecash-mainnet", "family": "ecash", "display_name": "eCash Mainnet",
          "fork_height": 973728, "network_magic": "eca5dcb7", "replay_lock_time": 499999998,
          "backends": [ { "kind": "esplora", "url": "https://esplora.mainnet.ecash.example" } ],
          "explorer_tx_template": "https://explorer.mainnet.ecash.example/tx/{txid}",
          "services": { "enforcer": { "url": "https://seed.mainnet.ecash.example/enforcer" } } },
        { "id": "betanet", "family": "ecash", "display_name": "Betanet",
          "fork_height": 967680, "replay_lock_time": 499999999,
          "backends": [ { "kind": "esplora", "url": "https://esplora.beta.ecash.ninja" } ],
          "explorer_tx_template": "https://explorer.beta.ecash.ninja/tx/{txid}" }
      ]
    }
    """

    private static func parse(_ json: String) throws -> RemoteEndpointConfig {
        try #require(RemoteEndpointConfig.parse(Data(json.utf8)))
    }

    private static func reset() {
        EcashMainnetLaunch.resetForTesting(offered: false)
        RemoteServiceOverrides.clearEsploraURLForTesting(for: .ecashMainnet)
        RemoteServiceOverrides.clearEsploraURLForTesting(for: .bitcoin)
    }

    // MARK: - Routing

    @Test func theStagedIdReachesTheMainnetCaseAndBetanetKeepsItsOwn() throws {
        let cfg = try Self.parse(Self.staged)
        #expect(cfg.networks.compactMap(\.walletNetwork) == [.bitcoin, .ecashMainnet, .ecashBeta])

        let backends = cfg.resolvedPrimaryBackends()
        #expect(backends.first { $0.network == .ecashMainnet }?.url == "https://esplora.mainnet.ecash.example")
        #expect(backends.first { $0.network == .ecashBeta }?.url == "https://esplora.beta.ecash.ninja")

        let heights = cfg.resolvedForkHeights()
        #expect(heights.first { $0.network == .ecashMainnet }?.height == 973_728)
        #expect(heights.first { $0.network == .ecashBeta }?.height == 967_680)

        let names = cfg.resolvedDisplayNames()
        #expect(names.first { $0.network == .ecashMainnet }?.name == "eCash Mainnet")
        #expect(names.first { $0.network == .ecashBeta }?.name == "Betanet")

        let enforcers = cfg.resolvedEnforcers()
        #expect(enforcers.first { $0.network == .ecashMainnet }?.url == "https://seed.mainnet.ecash.example/enforcer")
        #expect(enforcers.first { $0.network == .ecashBeta } == nil, "betanet's entry carries no enforcer here")
    }

    /// The dashboard block uses the same allow-list, so `"ecash-mainnet"` there means the same case.
    @Test func theDashboardIdMeansTheSameNetwork() {
        let dash = DashboardNetwork(id: "ecash-mainnet", displayName: "eCash", explorerURL: "https://e.example",
                                    releasesChannel: "mainnet")
        #expect(dash.walletNetwork == .ecashMainnet)
    }

    // MARK: - The fork watcher

    private static func fetcher(tips: [String: String]) -> DashboardFetch {
        { url in
            let host = url.host ?? ""
            guard let body = tips[host] else { return (Data(), 404) }
            return (Data(body.utf8), 200)
        }
    }

    @Test func doesNothingUntilTheConfigOffersMainnet() async {
        Self.reset()
        RemoteServiceOverrides.setEsploraURL("https://esplora.mainnet.drivechain.info", for: .bitcoin)
        let flipped = await ForkWatch.checkIfNeeded(fetch: Self.fetcher(tips: ["esplora.mainnet.drivechain.info": "999999"]))
        #expect(!flipped)
        #expect(WalletNetwork.currentEcash == .ecashBeta)
        Self.reset()
    }

    @Test func asksMainnetsOwnEsploraFirstThenBitcoins() async {
        Self.reset()
        EcashMainnetLaunch.resetForTesting(offered: true)
        RemoteServiceOverrides.setEsploraURL("https://esplora.mainnet.ecash.example", for: .ecashMainnet)
        RemoteServiceOverrides.setEsploraURL("https://esplora.mainnet.drivechain.info", for: .bitcoin)
        #expect(ForkWatch.candidateBases() == ["https://esplora.mainnet.ecash.example", "https://esplora.mainnet.drivechain.info"])

        // Mainnet's Esplora is down; Bitcoin's answers, below the height: not yet.
        var flipped = await ForkWatch.checkIfNeeded(fetch: Self.fetcher(tips: ["esplora.mainnet.drivechain.info": "973727\n"]))
        #expect(!flipped)
        #expect(WalletNetwork.currentEcash == .ecashBeta)

        // The fork block arrives.
        flipped = await ForkWatch.checkIfNeeded(fetch: Self.fetcher(tips: ["esplora.mainnet.drivechain.info": "973728"]))
        #expect(flipped)
        #expect(WalletNetwork.currentEcash == .ecashMainnet)

        // Already the default: the watcher is idle and never asks again.
        flipped = await ForkWatch.checkIfNeeded(fetch: { _ in Issue.record("fetched after the latch"); return (Data(), 500) })
        #expect(!flipped)
        Self.reset()
    }

    @Test func garbageAndErrorsMeanNotYet() async {
        Self.reset()
        EcashMainnetLaunch.resetForTesting(offered: true)
        RemoteServiceOverrides.setEsploraURL("https://esplora.mainnet.ecash.example", for: .ecashMainnet)
        for body in ["", "abc", "-5", "{\"height\":973728}"] {
            let flipped = await ForkWatch.checkIfNeeded(fetch: Self.fetcher(tips: ["esplora.mainnet.ecash.example": body]))
            #expect(!flipped, "body \(body)")
        }
        let failed = await ForkWatch.checkIfNeeded(fetch: { _ in throw DashboardError.http(503) })
        #expect(!failed)
        #expect(WalletNetwork.currentEcash == .ecashBeta)
        Self.reset()
    }

    /// Betanet is past 973,728 on its OWN chain; its tip must never be what flips the gate.
    @Test func betanetsTipIsNeverConsulted() {
        Self.reset()
        EcashMainnetLaunch.resetForTesting(offered: true)
        RemoteServiceOverrides.setEsploraURL("https://esplora.beta.ecash.ninja", for: .ecashBeta)
        #expect(ForkWatch.candidateBases().isEmpty)
        Self.reset()
    }

    @Test func parsesABareInteger() {
        #expect(ForkWatch.parseTip(Data("973728".utf8)) == 973_728)
        #expect(ForkWatch.parseTip(Data(" 973728\n".utf8)) == 973_728)
        #expect(ForkWatch.parseTip(Data("0".utf8)) == nil)
        #expect(ForkWatch.parseTip(Data("".utf8)) == nil)
    }
}
