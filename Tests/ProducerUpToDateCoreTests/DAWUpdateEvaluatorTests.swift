// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class DAWUpdateEvaluatorTests: XCTestCase {
    func testStaleReviewCannotClaimCurrentOrUpdateAndRemovedEntryClearsEvidence() {
        let installed = fixture(version: "1.0")
        let record = DAWReleaseRecord(definitionID: "fixture", latestVersion: "2.0", sourceURL: URL(string: "https://vendor.example/releases")!, checkedOn: "2026-01-01")
        let stale = DAWUpdateEvaluator.evaluate(installed, catalogue: [record], now: EvidenceFreshness.date("2026-09-05")!)
        XCTAssertEqual(stale.updateState, .unavailable)
        let cleared = DAWUpdateEvaluator.evaluate(stale, catalogue: [])
        XCTAssertEqual(cleared.updateState, .notChecked)
        XCTAssertNil(cleared.latestVersion)
        XCTAssertNil(cleared.updateSourceURL)
    }

    func testFindsUpdateFromReviewedRelease() {
        let result = DAWUpdateEvaluator.evaluate(
            fixture(version: "6.0.6"),
            catalogue: [release(version: "6.0.11")]
        )
        XCTAssertEqual(result.updateState, .updateAvailable)
        XCTAssertEqual(result.latestVersion, "6.0.11")
    }

    func testHandlesVersionWithBuildSuffix() {
        let installed = fixture(
            version: "12.4.3 (2026-01-01_build)"
        )
        let result = DAWUpdateEvaluator.evaluate(
            installed,
            catalogue: [release(version: "12.4.3")]
        )
        XCTAssertEqual(result.updateState, .current)
        XCTAssertEqual(installed.conciseInstalledVersion, "12.4.3")
    }

    func testMissingCatalogueStaysNotChecked() {
        let result = DAWUpdateEvaluator.evaluate(
            fixture(version: "3.6.0"),
            catalogue: []
        )
        XCTAssertEqual(result.updateState, .notChecked)
        XCTAssertNil(result.latestVersion)
    }

    func testNewerInstalledVersionDoesNotMakeStaleCatalogueClaim() {
        let result = DAWUpdateEvaluator.evaluate(
            fixture(version: "7.0"),
            catalogue: [release(version: "6.0.11")]
        )
        XCTAssertEqual(result.updateState, .unavailable)
    }

    private func fixture(version: String) -> InstalledDAWRecord {
        InstalledDAWRecord(
            id: "daw",
            definitionID: "fixture",
            name: "Fixture",
            vendor: "Vendor",
            bundleIdentifier: "com.vendor.fixture",
            displayVersion: version,
            buildVersion: nil,
            path: URL(fileURLWithPath: "/Applications/Fixture.app"),
            executablePath: nil,
            architectures: []
        )
    }

    private func release(version: String) -> DAWReleaseRecord {
        DAWReleaseRecord(
            definitionID: "fixture",
            latestVersion: version,
            sourceURL: URL(string: "https://vendor.example/releases")!,
            checkedOn: EvidenceFreshness.day(Date())
        )
    }
}
