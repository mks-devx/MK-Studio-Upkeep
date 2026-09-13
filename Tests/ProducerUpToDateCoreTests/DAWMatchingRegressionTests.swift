// SPDX-License-Identifier: AGPL-3.0-only
import XCTest
@testable import ProducerUpToDateCore

final class DAWMatchingRegressionTests: XCTestCase {
    let now = EvidenceFreshness.date("2026-09-05")!
    func installed(_ id: String, version: String) -> InstalledDAWRecord {
        .init(id: id, definitionID: id, name: id, vendor: "Fixture", bundleIdentifier: nil, displayVersion: version, buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Fixture.app"), executablePath: nil, architectures: [])
    }
    func testLiveBuildSuffixSupportsComparisonWithinTheSameMajorVersion() {
        let live = installed("ableton-live", version: "12.4.5 (2026-08-19_0123456789)")
        let release = DAWReleaseRecord(definitionID: "ableton-live", latestVersion: "12.4.5", sourceURL: URL(string: "https://www.ableton.com/en/release-notes/live-12/")!, checkedOn: "2026-09-05", majorVersion: 12)
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(live, catalogue: [release], now: now).updateState, .current)
        let unsupported = installed("ableton-live", version: "11.4.5 (2026-08-19_0123456789)")
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(unsupported, catalogue: [release], now: now).updateState, .notChecked)
    }
    func testReasonPrereleaseRemainsIncomparableWithStableRelease() {
        let release = DAWReleaseRecord(definitionID: "reason", latestVersion: "14.1.0", sourceURL: URL(string: "https://www.reasonstudios.com/")!, checkedOn: "2026-09-05", majorVersion: 14)
        let raw = installed("reason", version: "14.1d1 build 10000")
        let result = DAWUpdateEvaluator.evaluate(raw, catalogue: [release], now: now)
        XCTAssertEqual(result.latestVersion, "14.1.0")
        XCTAssertEqual(result.updateState, .unavailable, "A d100 build cannot silently become a stable release")
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(installed("reason", version: "14.1"), catalogue: [release], now: now).updateState, .current)
    }
}
