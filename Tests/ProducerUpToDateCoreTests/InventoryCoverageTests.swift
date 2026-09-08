// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class InventoryCoverageTests: XCTestCase {
    private let now = EvidenceFreshness.date("2026-09-05")!

    func testEveryProductReceivesAResultAndTotalsReconcile() {
        let products = [product("older", version: "1"), product("current", version: "2"),
            product("ahead", version: "3"), product("uncovered", version: "1", name: "Other"),
            product("identity", version: "1", uncertain: true), product("missing", version: nil)]
        let results = products.map { PluginUpdateEvaluator.evaluate($0, catalogue: [release()], now: now) }
        XCTAssertEqual(results.map(\.id), products.map(\.id))
        XCTAssertEqual(results.map(\.reason), [nil, nil, .installedVersionAhead, .noReviewedRelease, .identityNeedsReview, .missingReleaseVersion])
        let coverage = PluginUpdateCoverage(results: results)
        XCTAssertEqual(coverage.total, 6)
        XCTAssertEqual(coverage.updates, 1)
        XCTAssertEqual(coverage.current, 1)
        XCTAssertEqual(coverage.unresolved, 4)
        XCTAssertEqual(coverage.compared + coverage.unresolved, coverage.total)
        XCTAssertEqual(PluginUpdateCoverage(results: []).total, 0)
    }

    func testStaleDataGetsASpecificReasonAndNoCurrentCount() {
        let result = PluginUpdateEvaluator.evaluate(product("stale", version: "2"), catalogue: [release()],
            now: EvidenceFreshness.date("2026-12-05")!)
        XCTAssertEqual(result.reason, .staleEvidence)
        XCTAssertEqual(PluginUpdateCoverage(results: [result]).current, 0)
    }

    func testTokyoDawnReleasesDoNotMatchPaidGEEditionsOrOtherVendors() {
        // Synthetic versions isolate edition and vendor identity matching.
        let catalogue = ["TDR Nova", "TDR Kotelnikov", "TDR Molotok"].map {
            SyntheticCatalogueFixture.release($0, prefix: "com.tokyodawnlabs.")
        }
        for name in ["TDR Nova", "TDR Kotelnikov", "TDR Molotok"] {
            let old = "1.0", new = "2.0"
            let result = PluginUpdateEvaluator.evaluate(product(name, version: old, name: name), catalogue: catalogue, now: now)
            XCTAssertEqual(result.updateState, .updateAvailable)
            XCTAssertEqual(result.latestVersion, new)
            XCTAssertEqual(PluginUpdateEvaluator.evaluate(product(name, version: old, name: name + " GE"), catalogue: catalogue, now: now).reason, .noReviewedRelease)
        }
        XCTAssertEqual(PluginUpdateEvaluator.evaluate(product("spoof", version: "1", name: "TDR Nova", identifier: "com.other.nova"), catalogue: catalogue, now: now).reason, .noReviewedRelease)
    }

    func testCustomFolderFindsSupportedBundlesWithoutDroppingMalformedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for ext in ["component", "vst3", "vst", "clap"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested/Fixture.\(ext)"), withIntermediateDirectories: true)
        }
        // A nested helper bundle is not another top-level installed plugin.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Nested/Fixture.component/Contents/Helper.vst3"), withIntermediateDirectories: true)
        let config = ScanConfiguration.includingCustomFolders([root, root], enabledFormats: Set(PluginFormat.allCases))
        let locations = config.locations.filter { $0.url.path == root.path }
        XCTAssertEqual(locations.count, 4)
        let report = try PluginScanner().scan(configuration: .init(locations: locations))
        XCTAssertEqual(report.records.count, 4)
        XCTAssertTrue(report.records.allSatisfy { $0.issues.contains { $0.id == "missing-info-plist" } })
        let clapOnly = ScanConfiguration.includingCustomFolders([root], enabledFormats: [.clap])
        XCTAssertTrue(clapOnly.locations.allSatisfy { $0.format == .clap })
    }

    private func release() -> PluginReleaseRecord {
        .init(vendorIdentifierPrefixes: ["com.tokyodawnlabs."], productAliases: ["Fixture"], latestVersion: "2",
              sourceURL: URL(string: "https://www.tokyodawn.net/tdr-nova/")!, checkedOn: "2026-09-05")
    }

    private func product(_ id: String, version: String?, name: String = "Fixture", uncertain: Bool = false,
                         identifier: String = "com.TokyoDawnLabs.Fixture") -> NormalizedPluginProduct {
        let bundle = PluginBundleRecord(id: id, name: name, vendor: "Tokyo Dawn Labs", format: .audioUnit,
            bundleIdentifier: identifier, displayVersion: version, buildVersion: "999",
            path: URL(fileURLWithPath: "/tmp/Fixture.component"), executablePath: nil,
            architectures: [.arm64], fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        return .init(id: id, name: name, vendor: "Tokyo Dawn Labs", bundles: [bundle], confidence: .high,
                     matchEvidence: [], requiresVerification: uncertain)
    }
}
