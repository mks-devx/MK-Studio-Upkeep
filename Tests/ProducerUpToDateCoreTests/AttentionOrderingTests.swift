// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class AttentionOrderingTests: XCTestCase {
    private func issue(_ id: String, _ severity: ScanIssueSeverity, _ title: String) -> ScanIssue {
        ScanIssue(id: id, severity: severity, title: title, detail: "Fixture detail for \(title).")
    }
    private func product(_ name: String, vendor: String, issues: [ScanIssue]) -> NormalizedPluginProduct {
        let bundle = PluginBundleRecord(id: name, name: name, vendor: vendor, format: .audioUnit, bundleIdentifier: "fixture.\(name)",
            displayVersion: "1.0", buildVersion: nil, path: URL(fileURLWithPath: "/Library/\(name).component"), executablePath: nil,
            architectures: [.arm64], fileSize: nil, modifiedAt: nil, evidence: [], issues: issues)
        return NormalizedPluginProduct(id: name, name: name, vendor: vendor, bundles: [bundle], confidence: .high, matchEvidence: [], requiresVerification: false)
    }

    func testCriticalFirstThenKindThenVendorAndName() {
        let intel = issue("intel-only", .warning, "Intel-only build")
        let missing = issue("missing-version", .warning, "Version missing")
        let broken = issue("missing-executable", .critical, "Executable missing")
        let products = [
            product("Zeta", vendor: "Vendor B", issues: [intel]),
            product("Alpha", vendor: "Vendor B", issues: [missing]),
            product("Mid", vendor: "Vendor A", issues: [intel]),
            product("Late", vendor: "Vendor Z", issues: [intel, broken]),
            product("Beta", vendor: "Vendor A", issues: [missing])
        ]
        let names = AttentionOrdering.ordered(products).map(\.name)
        XCTAssertEqual(names, ["Late", "Mid", "Zeta", "Beta", "Alpha"],
                       "Critical first; then Intel-only rows grouped before Version missing; vendor then name inside a group")
        XCTAssertEqual(AttentionOrdering.primaryIssue(of: products[3])?.id, "missing-executable", "The row leads with its most severe finding")
        XCTAssertEqual(AttentionOrdering.primaryIssue(of: products[0])?.id, "intel-only")
        XCTAssertNil(AttentionOrdering.primaryIssue(of: product("Clean", vendor: "V", issues: [])))
    }

    func testIssueKindsFollowListOrderAndCountProductsOnce() {
        let intel = issue("intel-only", .warning, "Intel-only build")
        let broken = issue("missing-executable", .critical, "Executable missing")
        let products = [
            product("One", vendor: "V", issues: [intel]),
            product("Two", vendor: "V", issues: [intel, broken]),
            product("Three", vendor: "V", issues: [broken])
        ]
        let kinds = AttentionOrdering.issueKinds(in: products)
        XCTAssertEqual(kinds.map(\.title), ["Executable missing", "Intel-only build"])
        XCTAssertEqual(kinds.map(\.count), [2, 2])
        XCTAssertTrue(AttentionOrdering.issueKinds(in: []).isEmpty)
    }

    func testOrderingIsStableAndKeepsEveryProduct() {
        let intel = issue("intel-only", .warning, "Intel-only build")
        let products = (0..<50).map { product("P\(String(format: "%02d", $0))", vendor: "V", issues: [intel]) }
        let once = AttentionOrdering.ordered(products.shuffled())
        XCTAssertEqual(once.map(\.name), products.map(\.name))
        XCTAssertEqual(AttentionOrdering.ordered(once).map(\.name), once.map(\.name))
    }
}
