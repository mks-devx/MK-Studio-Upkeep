// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class DAWMatchingRegressionTests: XCTestCase {
    let now = EvidenceFreshness.date("2026-09-05")!
    func installed(_ id: String, version: String) -> InstalledDAWRecord {
        .init(id: id, definitionID: id, name: id, vendor: "Fixture", bundleIdentifier: nil, displayVersion: version, buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Fixture.app"), executablePath: nil, architectures: [])
    }
    func testLiveBuildSuffixEnablesCheckAndComparison() {
        let live = installed("ableton-live", version: "12.4.5 (2026-08-19_0123456789)")
        let release = DAWReleaseRecord(definitionID: "ableton-live", latestVersion: "12.4.5", sourceURL: DirectVendor.live.url, checkedOn: "2026-09-05", majorVersion: 12)
        XCTAssertEqual(DAWUpdateSource.checker(for: live, includeInactive: true), .live)
        XCTAssertNil(DAWUpdateSource.checker(for: live), "No live update reader is enabled")
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(live, catalogue: [release], now: now).updateState, .current)
        let unsupported = installed("ableton-live", version: "11.4.5 (2026-08-19_0123456789)")
        XCTAssertNil(DAWUpdateSource.checker(for: unsupported, includeInactive: true))
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(unsupported, catalogue: [release], now: now).updateState, .notChecked)
        XCTAssertNil(DAWUpdateSource.checker(for: installed("ableton-live", version: "12.4.5 (unverified suffix)"), includeInactive: true))
    }
    func testReasonSourceRejectsWrongFamilyAndReorderedReleases() throws {
        let page = "<h3>Reason 14.1.0 Release Notes</h3><h3>Reason 14.0.2 Release Notes</h3>"
        let release = try DirectVendorChecks.dawRelease(from: .init(vendor: .reason, checkedAt: now, page: page), now: now)
        XCTAssertEqual(release.latestVersion, "14.1.0")
        XCTAssertEqual(release.majorVersion, 14)
        for invalid in [page.replacingOccurrences(of: "Reason", with: "Reason Companion"), page.replacingOccurrences(of: "14.0.2", with: "14.2.0"), page.replacingOccurrences(of: "14.", with: "13.")] {
            XCTAssertThrowsError(try DirectVendorChecks.dawRelease(from: .init(vendor: .reason, checkedAt: now, page: invalid), now: now))
        }
        let raw = installed("reason", version: "14.1d1 build 10000")
        XCTAssertEqual(DAWUpdateSource.checker(for: raw, includeInactive: true), .reason)
        XCTAssertNil(DAWUpdateSource.checker(for: raw), "Reason has no documented access basis; website handoff only")
        let result = DAWUpdateEvaluator.evaluate(raw, catalogue: [release], now: now)
        XCTAssertEqual(result.latestVersion, "14.1.0")
        XCTAssertEqual(result.updateState, .unavailable, "A d100 build cannot silently become a stable release")
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(installed("reason", version: "14.1"), catalogue: [release], now: now).updateState, .current)
    }
}
