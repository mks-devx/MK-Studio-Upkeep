// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class NotCheckedReasonTests: XCTestCase {
    private func bundle(_ id: String?) -> PluginBundleRecord {
        PluginBundleRecord(id: "b-\(id ?? "none")", name: "Fixture", vendor: nil, format: .audioUnit, bundleIdentifier: id, displayVersion: "1.0",
            buildVersion: nil, path: URL(fileURLWithPath: "/Library/Fixture.component"), executablePath: nil, architectures: [.arm64],
            fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
    }
    private func product(_ ids: [String?], unverified: Bool = false) -> NormalizedPluginProduct {
        NormalizedPluginProduct(id: (ids.first ?? nil) ?? "x", name: "Fixture", vendor: "Vendor", bundles: ids.map(bundle),
            confidence: unverified ? .low : .high, matchEvidence: [], requiresVerification: unverified)
    }

    func testEveryUncomparedProductGetsExactlyOneActionableReason() {
        let catalogue = [PluginReleaseRecord(vendorIdentifierPrefixes: ["com.fabfilter."], productAliases: ["Pro-Q 4"], latestVersion: "4.13",
                                             sourceURL: URL(string: "https://www.fabfilter.com/download")!, checkedOn: "2026-09-05")]
        let now = EvidenceFreshness.date("2026-09-06")!
        func reason(_ p: NormalizedPluginProduct) -> NotCheckedReason? { PluginUpdateEvaluator.evaluate(p, catalogue: catalogue, now: now).notCheckedReason }
        XCTAssertEqual(reason(product(["com.arturia.pigments"])), .vendorApp)
        XCTAssertEqual(reason(product(["com.fabfilter.mystery"], unverified: true)), .confirmIdentity)
        XCTAssertEqual(reason(product(["com.arturia.x", nil])), .fileWithoutIdentifier)
        XCTAssertEqual(reason(product(["com.nobody.obscure"])), .notInCatalogue)
        XCTAssertNil(reason(NormalizedPluginProduct(id: "q", name: "Pro-Q 4", vendor: "FabFilter", bundles: [bundle("com.fabfilter.proq4")],
                                                    confidence: .high, matchEvidence: [], requiresVerification: false)), "Compared products have no reason")
        let kinds = NotCheckedReason.kinds(in: [product(["com.nobody.a"]), product(["com.nobody.b"]), product(["com.arturia.c"])].map {
            PluginUpdateEvaluator.evaluate($0, catalogue: catalogue, now: now) })
        XCTAssertEqual(kinds.map(\.title), [NotCheckedReason.notInCatalogue.rawValue, NotCheckedReason.vendorApp.rawValue])
        XCTAssertEqual(kinds.map(\.count), [2, 1])
    }
}
