// Copyright (C) 2026 LayerTwo Labs and contributors
// Licensed under the GNU General Public License v2.0 or later
// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import WalletService

/// The clipboard rules for seed-equivalent text. The pasteboard itself can't be exercised here;
/// these pin the decisions the platform glue makes around it.
final class ClipboardPolicyTests: XCTestCase {

    func testLifetimeIsShortButUsable() {
        // A terminal paste takes seconds; a forgotten clipboard lasts forever. Pin the window so a
        // casual edit can't silently turn one into the other.
        XCTAssertEqual(ClipboardPolicy.sensitiveLifetimeSeconds, 60)
        XCTAssertGreaterThanOrEqual(ClipboardPolicy.sensitiveLifetimeSeconds, 15)
        XCTAssertLessThanOrEqual(ClipboardPolicy.sensitiveLifetimeSeconds, 120)
    }

    func testLabelDescribesNothing() {
        // The plain copy labels clips "address"; a seed must not be labelled at all.
        XCTAssertEqual(ClipboardPolicy.sensitiveLabel, "")
    }

    func testClearsWhenClipboardStillHoldsTheSeed() {
        XCTAssertTrue(ClipboardPolicy.shouldClear(current: "seed-text", copied: "seed-text"))
    }

    func testLeavesALaterUserCopyAlone() {
        XCTAssertFalse(ClipboardPolicy.shouldClear(current: "bc1qsomething", copied: "seed-text"))
    }

    func testClearsWhenClipboardIsUnreadableOrEmpty() {
        // nil = the OS hid the clipboard from us (app lost focus); it may still hold the seed.
        XCTAssertTrue(ClipboardPolicy.shouldClear(current: nil, copied: "seed-text"))
        XCTAssertTrue(ClipboardPolicy.shouldClear(current: "", copied: "seed-text"))
    }
}
