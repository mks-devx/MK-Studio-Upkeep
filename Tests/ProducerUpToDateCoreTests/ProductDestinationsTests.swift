// SPDX-License-Identifier: AGPL-3.0-only
import XCTest
@testable import ProducerUpToDateCore

final class ProductDestinationsTests: XCTestCase {
    func product(_ name: String, id: String, version: String = "2.01") -> NormalizedPluginProduct {
        let bundle = PluginBundleRecord(id: "fixture", name: name, vendor: "Example", format: .audioUnit, bundleIdentifier: id,
            displayVersion: version, buildVersion: nil, path: URL(fileURLWithPath: "/fixtures/example.component"), executablePath: nil,
            architectures: [.arm64], fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        return .init(id: "fixture", name: name, vendor: "Example", bundles: [bundle], confidence: .high, matchEvidence: [], requiresVerification: false)
    }
    func testEachVendorGetsOnlyItsOwnDestination() {
        let antelope = product("Fixture", id: "com.antelopeaudio.fixture")
        XCTAssertEqual(ProductDestinations.plugin(antelope)?.url.host, "support.antelopeaudio.com")
        XCTAssertEqual(ProductDestinations.plugin(antelope)?.referenceURL.host, "support.antelopeaudio.com")
        XCTAssertEqual(ProductDestinations.plugin(antelope)?.reviewedOn, "2026-09-08")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.antelopeaudio.fixture"])?.name, "Antelope Launcher")
        XCTAssertEqual(ProductDestinations.plugin(product("Fixture", id: "com.fabfilter.fixture"))?.url.host, "www.fabfilter.com")
        XCTAssertNil(ProductDestinations.plugin(product("FabFilter Pro-Q 4", id: "com.other.fixture")))
        XCTAssertNil(ProductDestinations.plugin(product("Fixture", id: "com.fabfilter-spoof.fixture")))
    }
    func testEveryDirectDeveloperEntryHasValidReviewEvidence() {
        XCTAssertTrue(ProductDestinations.reviewEvidenceIsComplete)
    }
    func testReviewEvidenceRejectsMalformedDatesAndUnsafeReferences() {
        XCTAssertFalse(OfficialLinkReview.isValid(date: "2026-02-30"))
        XCTAssertFalse(OfficialLinkReview.isValid(date: "8 September 2026"))
        XCTAssertFalse(OfficialLinkReview.isComplete(referenceURL: URL(string: "http://example.com")!, reviewedOn: "2026-09-08"))
        XCTAssertFalse(OfficialLinkReview.isComplete(referenceURL: URL(string: "https://user@example.com")!, reviewedOn: "2026-09-08"))
        XCTAssertTrue(OfficialLinkReview.isComplete(referenceURL: URL(string: "https://example.com/support")!, reviewedOn: "2026-09-08"))
    }
    func testOfficialWebsiteRemainsAvailableForAnOlderInstalledEdition() {
        let older = product("ShaperBox 2", id: "de.cableguys.fixture")
        XCTAssertEqual(ProductDestinations.plugin(older)?.url.host, "www.cableguys.com")
        XCTAssertNil(ProductDestinations.plugin(product("ShaperBox 2", id: "com.other.fixture")))
    }
}
