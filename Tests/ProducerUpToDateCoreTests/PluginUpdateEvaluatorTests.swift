// SPDX-License-Identifier: BUSL-1.1
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

    func testNewerEditionIsReportedSeparatelyFromUpdates() {
        let now = EvidenceFreshness.date("2026-09-06")!
        func edition(_ alias: String, _ version: String, _ number: Int, family: String = "fabfilter:pro-q",
                     prefix: String = "com.fabfilter.", checkedOn: String = "2026-09-05") -> PluginReleaseRecord {
            .init(vendorIdentifierPrefixes: [prefix], productAliases: [alias, "FabFilter \(alias)"], latestVersion: version,
                  sourceURL: URL(string: "https://www.fabfilter.com/download")!, checkedOn: checkedOn, family: family, edition: number)
        }
        let catalogue = [edition("Pro-Q 3", "3.29", 3), edition("Pro-Q 4", "4.13", 4)]
        let older = PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.29"), catalogue: catalogue, now: now)
        XCTAssertEqual(older.updateState, .current, "The installed edition is compared on its own terms")
        XCTAssertEqual(older.newerEdition?.name, "Pro-Q 4")
        XCTAssertEqual(older.newerEdition?.edition, 4)
        XCTAssertEqual(older.newerEdition?.latestVersion, "4.13")
        XCTAssertEqual(older.newerEdition?.sourceURL.host, "www.fabfilter.com")
        let behind = PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.20"), catalogue: catalogue, now: now)
        XCTAssertEqual(behind.updateState, .updateAvailable)
        XCTAssertEqual(behind.latestVersion, "3.29", "The update stays within the installed edition")
        XCTAssertEqual(behind.newerEdition?.name, "Pro-Q 4")
        XCTAssertNil(PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 4", version: "4.13"), catalogue: catalogue, now: now).newerEdition)
        XCTAssertNil(PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.29", requiresVerification: true), catalogue: catalogue, now: now).newerEdition)
        let stale = [catalogue[0], edition("Pro-Q 4", "4.13", 4, checkedOn: "2026-07-01")]
        XCTAssertNil(PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.29"), catalogue: stale, now: now).newerEdition, "Stale edition evidence is not shown")
        let otherVendor = [catalogue[0], edition("Pro-Q 4", "4.13", 4, prefix: "com.other.")]
        XCTAssertNil(PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.29"), catalogue: otherVendor, now: now).newerEdition)
        let ambiguous = catalogue + [edition("Pro-Q 4 Bundle", "4.13", 4)]
        XCTAssertNil(PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.29"), catalogue: ambiguous, now: now).newerEdition, "Two records claiming one edition yield nothing")
        let unlinked = [release(product: "Pro-Q 3", version: "3.29"), release(product: "Pro-Q 4", version: "4.13")]
        XCTAssertNil(PluginUpdateEvaluator.evaluate(product(name: "Pro-Q 3", version: "3.29"), catalogue: unlinked, now: now).newerEdition, "No family link, no edition claim")
        let coverage = PluginUpdateCoverage(results: [older, behind])
        XCTAssertEqual(coverage.upgrades, 2)
        XCTAssertEqual(coverage.updates, 1)
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
