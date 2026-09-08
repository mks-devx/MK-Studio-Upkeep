// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class EmptyCatalogueDefaultsTests: XCTestCase {
    func testDefaultCataloguesContainNoImplicitReleaseOrArchitectureEvidence() {
        XCTAssertTrue(ReviewedPluginCatalogue.bundled.isEmpty)
        XCTAssertTrue(ReviewedDAWCatalogue.bundled.isEmpty)
        XCTAssertTrue(ReviewedArchitectureSupportCatalogue.bundled.isEmpty)
        let bundle = PluginBundleRecord(id: "fixture", name: "Fixture", vendor: "Example", format: .audioUnit,
            bundleIdentifier: "com.example.fixture", displayVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/tmp/Fixture.component"), executablePath: nil, architectures: [.x86_64],
            fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        let product = NormalizedPluginProduct(id: "fixture", name: bundle.name, vendor: bundle.vendor,
            bundles: [bundle], confidence: .high, matchEvidence: [], requiresVerification: false)
        let update = PluginUpdateEvaluator.evaluate(product, catalogue: ReviewedPluginCatalogue.bundled)
        XCTAssertEqual(update.reason, .noReviewedRelease)
        XCTAssertNil(update.latestVersion)
        XCTAssertNil(update.newerEdition)
        XCTAssertEqual(ProductArchitectureSupportEvaluator.evaluate(product: product,
            catalogue: ReviewedArchitectureSupportCatalogue.bundled), .nativeReleaseNotConfirmed)
    }
}
