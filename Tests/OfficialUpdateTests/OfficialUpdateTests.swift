// SPDX-License-Identifier: MPL-2.0
import XCTest
import ProducerUpToDateCore
@testable import OfficialUpdateSupport

final class OfficialUpdateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_789_000_000)
    func testDirectoryHasIdentifiersButNoReleaseFacts() throws {
        let directory = try OfficialSourceDirectory.bundled()
        XCTAssertEqual(directory.entries.count, 3)
        XCTAssertEqual(directory.match(identifier: "com.fabfilter.Pro-Q.AU.3", name: "FabFilter Pro-Q 3", version: "3.01", kind: .plugin)?.id, "fabfilter-pro-q-3")
        XCTAssertNil(directory.match(identifier: "com.fabfilter.Pro-Q.AU.3", name: "FabFilter Pro-Q 4", version: "4.01", kind: .plugin))
        XCTAssertNil(directory.match(identifier: "com.fabfilter.spoof", name: "FabFilter Pro-Q 4", version: "4.01", kind: .plugin))
        XCTAssertNil(directory.match(identifier: "com.cockos.reaper", name: "REAPER", version: "6.99", kind: .daw))
    }
    func testMacReleaseNeedsUniqueHeadingAndMatchingInstaller() throws {
        let entry = try OfficialSourceDirectory.bundled().entries.first { $0.id == "fabfilter-pro-q-4" }!
        let page = #"<h2>Download FabFilter Pro-Q 4</h2><p>Equalizer<br>4.02 &mdash; Jan 1, 2025</p><a href="https://cdn-b.fabfilter.com/downloads/ffproq402.dmg">Download for macOS</a>"#
        XCTAssertEqual(try OfficialReleaseParser.version(Data(page.utf8), entry: entry), "4.02")
        for invalid in [page + page, page.replacingOccurrences(of: "ffproq402", with: "ffproq403"), page.replacingOccurrences(of: "macOS", with: "Windows"), page.replacingOccurrences(of: "cdn-b.fabfilter.com", with: "other.example")] {
            XCTAssertThrowsError(try OfficialReleaseParser.version(Data(invalid.utf8), entry: entry))
        }
    }
    func testPerCopyComparisonAndFreshness() throws {
        let entry = try OfficialSourceDirectory.bundled().entries.first!
        let older = OfficialObservation(copyID: "a", entry: entry, installed: "4.01", latest: "4.02", checkedAt: now)
        let equal = OfficialObservation(copyID: "b", entry: entry, installed: "4.02", latest: "4.02", checkedAt: now)
        XCTAssertEqual(older.state(at: now), .update)
        XCTAssertEqual(equal.state(at: now), .matched)
        XCTAssertEqual(older.state(at: now.addingTimeInterval(86401)), .stale)
        XCTAssertEqual(older.state(at: now.addingTimeInterval(-1)), .stale)
        XCTAssertEqual(OfficialObservation(copyID: "c", entry: entry, installed: "4.03", latest: "4.02", checkedAt: now).state(at: now), .ahead)
        XCTAssertEqual(OfficialObservation(copyID: "c", entry: entry, installed: "4.01 beta", latest: "4.02", checkedAt: now).state(at: now), .ambiguous)
    }
    func testRowSummaryDoesNotHidePartialCoverageOrStaleness() throws {
        let entry = try OfficialSourceDirectory.bundled().entries[0]
        let result = OfficialObservation(copyID: "a", entry: entry, installed: "4.01", latest: "4.02", checkedAt: now)
        XCTAssertEqual(OfficialProductSummary.label(total: 2, results: [result], now: now), "Update available · 1 of 2 copies")
        XCTAssertEqual(OfficialProductSummary.label(total: 2, results: [result], now: now.addingTimeInterval(86401)), "Check expired")
        let matched = OfficialObservation(copyID: "b", entry: entry, installed: "4.02", latest: "4.02", checkedAt: now)
        XCTAssertEqual(OfficialProductSummary.label(total: 2, results: [matched], now: now), "Partly checked · 1 of 2 copies")
    }
    func testOptInPrecedesAllNetworkWork() throws {
        XCTAssertThrowsError(try OfficialCheckRunner.check([], allowNetwork: false) { _ in
            XCTFail("Network called without opt-in"); return Data()
        })
    }
}
