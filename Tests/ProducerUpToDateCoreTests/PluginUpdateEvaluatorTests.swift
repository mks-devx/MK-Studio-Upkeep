// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class PluginUpdateEvaluatorTests: XCTestCase {
    func testStaleAndFutureReviewDatesCannotClaimUpdate() {
        for date in ["2026-01-01", "2026-09-06", "invalid"] {
            let record = PluginReleaseRecord(vendorIdentifierPrefixes: ["com.fabfilter."], productAliases: ["Pro-Q 4"], latestVersion: "4.13", sourceURL: URL(string: "https://www.fabfilter.com/download")!, checkedOn: date)
            let result = PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 4", version: "4.11"), catalogue: [record], now: EvidenceFreshness.date("2026-09-05")!)
            XCTAssertEqual(result.updateState, .unavailable)
        }
    }

    func testFindsUpdateForExactReviewedProduct() {
        let result = PluginUpdateEvaluator.evaluate(
            product(name: "FabFilter Pro-Q 4", version: "4.11"),
            catalogue: [release(product: "Pro-Q 4", version: "4.13")]
        )

        XCTAssertEqual(result.updateState, .updateAvailable)
        XCTAssertEqual(result.latestVersion, "4.13")
    }

    func testMatchesAliasWithoutVendorPrefix() {
        let result = PluginUpdateEvaluator.evaluate(
            product(name: "Pro-C 3", version: "3.02"),
            catalogue: [release(product: "Pro-C 3", version: "3.02")]
        )

        XCTAssertEqual(result.updateState, .current)
    }

    func testDoesNotCrossMajorProductVersions() {
        let result = PluginUpdateEvaluator.evaluate(
            product(name: "FabFilter Pro-Q 3", version: "3.27"),
            catalogue: [release(product: "Pro-Q 4", version: "4.13")]
        )

        XCTAssertEqual(result.updateState, .notChecked)
    }

    func testRequiresVerifiedIdentity() {
        let result = PluginUpdateEvaluator.evaluate(
            product(
                name: "FabFilter Pro-Q 4",
                version: "4.11",
                requiresVerification: true
            ),
            catalogue: [release(product: "Pro-Q 4", version: "4.13")]
        )

        XCTAssertEqual(result.updateState, .notChecked)
    }

    func testMultipleInstalledVersionsCannotMakeUpdateClaim() {
        let first = bundle(name: "FabFilter Pro-Q 4", version: "4.11")
        let second = bundle(
            name: "FabFilter Pro-Q 4",
            version: "4.12",
            format: .vst3
        )
        let product = NormalizedPluginProduct(
            id: "product",
            name: "FabFilter Pro-Q 4",
            vendor: "FabFilter",
            bundles: [first, second],
            confidence: .high,
            matchEvidence: [],
            requiresVerification: false
        )

        let result = PluginUpdateEvaluator.evaluate(
            product,
            catalogue: [release(product: "Pro-Q 4", version: "4.13")]
        )

        XCTAssertEqual(result.updateState, .unavailable)
    }

    func testNewerInstalledVersionDoesNotTrustStaleCatalogue() {
        let result = PluginUpdateEvaluator.evaluate(
            product(name: "FabFilter Pro-Q 4", version: "4.14"),
            catalogue: [release(product: "Pro-Q 4", version: "4.13")]
        )

        XCTAssertEqual(result.updateState, .unavailable)
    }

    private func product(
        name: String,
        version: String,
        requiresVerification: Bool = false
    ) -> NormalizedPluginProduct {
        NormalizedPluginProduct(
            id: "product",
            name: name,
            vendor: "FabFilter",
            bundles: [bundle(name: name, version: version)],
            confidence: requiresVerification ? .low : .high,
            matchEvidence: [],
            requiresVerification: requiresVerification
        )
    }

    private func bundle(
        name: String,
        version: String,
        format: PluginFormat = .audioUnit
    ) -> PluginBundleRecord {
        PluginBundleRecord(
            id: "\(name)-\(format.rawValue)",
            name: name,
            vendor: "FabFilter",
            format: format,
            bundleIdentifier: "com.fabfilter.fixture",
            displayVersion: version,
            buildVersion: nil,
            path: URL(fileURLWithPath: "/Library/\(name).component"),
            executablePath: nil,
            architectures: [.arm64, .x86_64],
            fileSize: nil,
            modifiedAt: nil,
            evidence: [],
            issues: []
        )
    }

    private func release(
        product: String,
        version: String
    ) -> PluginReleaseRecord {
        PluginReleaseRecord(
            vendorIdentifierPrefixes: ["com.fabfilter."],
            productAliases: [product, "FabFilter \(product)"],
            latestVersion: version,
            sourceURL: URL(string: "https://www.fabfilter.com/download")!,
            checkedOn: EvidenceFreshness.day(Date())
        )
    }
}
