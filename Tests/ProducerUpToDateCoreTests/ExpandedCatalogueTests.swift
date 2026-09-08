// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class ExpandedCatalogueTests: XCTestCase {
    private let now = EvidenceFreshness.date("2026-09-05")!
    private var catalogue: [PluginReleaseRecord] { [SyntheticCatalogueFixture.release("Fixture Filter")] }

    func testExplicitEvidenceComparesNormalizedAUAndVST3Fixtures() {
        // Real identifiers exercise vendor normalization; versions are invented test inputs.
        for (name, vendor, identifier, prefix) in [
            ("kHs Filter", "Kilohearts", "com.kiloHearts.Filter", "com.kilohearts."),
            ("TAL Sampler", "TAL-Togu Audio Line", "ch.toguaudioline.talsampler", "ch.toguaudioline."),
            ("ValhallaVintageVerb", "Valhalla DSP, LLC", "com.ValhallaDSP.ValhallaVintageVerb", "com.valhalladsp.")
        ] {
            let records = [bundle(name, vendor, identifier, "1.0", .audioUnit), bundle(name, vendor, identifier, "1.0", .vst3)]
            let products = ProductNormalizer().normalize(records: records).products
            XCTAssertEqual(products.count, 1, name)
            guard let product = products.first else { continue }
            XCTAssertFalse(product.requiresVerification, name)
            let evidence = [SyntheticCatalogueFixture.release(name, prefix: prefix)]
            let result = PluginUpdateEvaluator.evaluate(product, catalogue: evidence, now: now)
            XCTAssertEqual(result.updateState, .updateAvailable, name)
            XCTAssertEqual(result.latestVersion, "2.0", name)
        }
    }

    func testUnreviewedProductsAndImpostorVendorsDoNotProduceClaims() {
        XCTAssertEqual(evaluate("Fixture Filter", "com.example.filter", "2.0").updateState, .current)
        for (name, identifier) in [("Unreviewed Fixture", "com.example.filter"),
                                   ("Fixture Filter", "com.other.filter"),
                                   ("Fixture Filter", "com.example-impostor.filter")] {
            let result = evaluate(name, identifier, "2.0")
            XCTAssertNil(result.latestVersion)
            XCTAssertEqual(result.reason, .noReviewedRelease)
        }
    }

    func testReviewedVendorSpellingsGroupFormatsWithoutLosingVersionDifferences() {
        for (name, first, second, id) in [
            ("TAL-BassLine-101", "TAL-Togu Audio Line", "toguaudioline", "ch.toguaudioline.talbassline101"),
            ("ValhallaVintageVerb", "Valhalla DSP, LLC", "ValhallaDSP", "com.ValhallaDSP.ValhallaVintageVerb")
        ] {
            let bundles = [bundle(name, first, id, "1.0", .audioUnit), bundle(name, second, id, "1.1", .vst3)]
            let products = ProductNormalizer().normalize(records: bundles).products
            XCTAssertEqual(products.count, 1, name)
            guard let product = products.first else { continue }
            XCTAssertEqual(product.bundles.count, 2)
            XCTAssertEqual(product.installedVersions, ["1.0", "1.1"])
            XCTAssertEqual(PluginUpdateEvaluator.evaluate(product, catalogue: [SyntheticCatalogueFixture.release(name, prefix: id.hasPrefix("ch.") ? "ch.toguaudioline." : "com.valhalladsp.")], now: now).reason, .differentInstalledVersions)
        }
        let unrelated = [bundle("Filter", "Kilohearts", "com.kilohearts.Filter", "1", .audioUnit),
                         bundle("Filter", "Another Vendor", "com.other.Filter", "1", .vst3)]
        XCTAssertEqual(ProductNormalizer().normalize(records: unrelated).products.count, 2)
    }

    func testUnreviewedEditionsRemainSeparate() {
        for name in ["Fixture Filter 2", "Fixture Filter Pro", "Fixture Filter Legacy"] {
            XCTAssertEqual(evaluate(name, "com.example.filter", "1.0").reason, .noReviewedRelease, name)
        }
    }

    func testExplicitReleaseEvidenceExpires() {
        XCTAssertEqual(evaluate("Fixture Filter", "com.example.filter", "2.0").updateState, .current)
        let p = product([bundle("Fixture Filter", "Example", "com.example.filter", "2.0", .audioUnit)])
        let expired = PluginUpdateEvaluator.evaluate(p, catalogue: catalogue, now: EvidenceFreshness.date("2026-10-06")!)
        XCTAssertEqual(expired.reason, .staleEvidence)
    }

    func testEvidenceDoesNotBypassMixedVersionsOrUncertainIdentity() {
        let bundles = [bundle("Fixture Filter", "Example", "com.example.filter", "1.0", .audioUnit),
                       bundle("Fixture Filter", "Example", "com.example.filter", "2.0", .vst3)]
        XCTAssertEqual(PluginUpdateEvaluator.evaluate(product(bundles), catalogue: catalogue, now: now).reason, .differentInstalledVersions)
        XCTAssertEqual(PluginUpdateEvaluator.evaluate(product(bundles, uncertain: true), catalogue: catalogue, now: now).reason, .identityNeedsReview)
        let mixedVendor = [bundles[0], bundle("Fixture Filter", "Other", "com.other.filter", "1.0", .vst3)]
        XCTAssertEqual(PluginUpdateEvaluator.evaluate(product(mixedVendor), catalogue: catalogue, now: now).reason, .noReviewedRelease)
    }

    func testReleaseNotesAreProductAndVersionBound() throws {
        let snapshot = SyntheticCatalogueFixture.snapshot
        let id = snapshot.plugins[0].catalogueID
        let notes = ReleaseNotesQuery.releases(productID: id, installed: "2.0", available: "3.0", notes: snapshot.releaseNotes, now: now)
        XCTAssertEqual(notes.map(\.version), ["3.0"])
        XCTAssertFalse(try XCTUnwrap(notes.first).highlights.isEmpty)
        XCTAssertTrue(ReleaseNotesQuery.releases(productID: id, installed: "3.0", available: "3.0", notes: snapshot.releaseNotes, now: now).isEmpty)
        XCTAssertTrue(ReleaseNotesQuery.releases(productID: "other-product", installed: "2.0", available: "3.0", notes: snapshot.releaseNotes, now: now).isEmpty)
    }

    private func evaluate(_ name: String, _ identifier: String, _ version: String) -> PluginUpdateResult {
        PluginUpdateEvaluator.evaluate(product([bundle(name, "Fixture", identifier, version, .audioUnit)]), catalogue: catalogue, now: now)
    }

    private func product(_ bundles: [PluginBundleRecord], uncertain: Bool = false) -> NormalizedPluginProduct {
        .init(id: "fixture", name: bundles[0].name, vendor: bundles[0].vendor, bundles: bundles,
              confidence: .high, matchEvidence: [], requiresVerification: uncertain)
    }

    private func bundle(_ name: String, _ vendor: String, _ identifier: String, _ version: String, _ format: PluginFormat) -> PluginBundleRecord {
        .init(id: format.rawValue, name: name, vendor: vendor, format: format,
              bundleIdentifier: identifier, displayVersion: version, buildVersion: nil,
              path: URL(fileURLWithPath: "/tmp/Fixture.\(format == .audioUnit ? "component" : "vst3")"),
              executablePath: nil, architectures: [.arm64, .x86_64], fileSize: nil,
              modifiedAt: nil, evidence: [], issues: [])
    }
}
