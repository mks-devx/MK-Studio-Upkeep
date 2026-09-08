// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class PluginCategoryTests: XCTestCase {
    func testMenuCountsMatchClassificationAndRebuildForFilteredCandidates() {
        func product(_ id: String, _ type: String?) -> NormalizedPluginProduct {
            let evidence: [VersionEvidence] = type.map { [.init(kind: .vst3ModuleInfo, field: "Classes[0].Sub Categories", value: $0)] } ?? []
            let record = PluginBundleRecord(id: id, name: id, vendor: "Example", format: .vst3,
                bundleIdentifier: "com.example." + id, displayVersion: "1.0", buildVersion: nil,
                path: URL(fileURLWithPath: "/synthetic/" + id + ".vst3"), executablePath: nil,
                architectures: [], fileSize: nil, modifiedAt: nil, evidence: evidence, issues: [])
            return ProductNormalizer().normalize(records: [record]).products[0]
        }
        let products = [product("one", "Instrument|Synth|Sampler"), product("two", "Fx|EQ|EQ"), product("three", nil)]
        let counts = PluginCategoryCounts(products: products)
        XCTAssertEqual(counts.total, 3)
        for category in PluginCategory.allCases {
            XCTAssertEqual(counts.categories[category, default: 0], products.filter { $0.category == category }.count)
        }
        for role in PluginRoleTags.all {
            XCTAssertEqual(counts.roles[role, default: 0], products.filter { $0.roleTags.contains(role) }.count)
        }
        XCTAssertEqual(counts.roles["EQ"], 1)
        let narrowed = PluginCategoryCounts(products: [products[0]])
        XCTAssertEqual(narrowed.total, 1)
        XCTAssertNil(narrowed.roles["EQ"])
        XCTAssertTrue(PluginCategoryCounts(products: []).categories.isEmpty)
    }

    func testDeclaredTypesUnknownAndConflicts() {
        func au(_ value: String) -> VersionEvidence { .init(kind: .audioComponent, field: "AudioComponents[0].type", value: value) }
        XCTAssertEqual(PluginCategory.classify(evidence: [au("aumu")]), .instrument)
        XCTAssertEqual(PluginCategory.classify(evidence: [au("aufx"), au("aumf")]), .audioEffect)
        XCTAssertEqual(PluginCategory.classify(evidence: [au("aumi")]), .midiEffect)
        XCTAssertEqual(PluginCategory.classify(evidence: [au("aumu"), au("aufx")]), .uncategorised)
        XCTAssertEqual(PluginCategory.classify(evidence: [au("future")]), .uncategorised)
        XCTAssertEqual(PluginCategory.classify(evidence: []), .uncategorised)
        XCTAssertEqual(PluginCategory.classify(evidence: [.init(kind: .inferred, field: "Name", value: "Synth EQ")]), .uncategorised)
        XCTAssertEqual(PluginCategory.classify(evidence: [.init(kind: .vst3ModuleInfo, field: "Classes[0].Sub Categories", value: "Fx|Instrument")]), .uncategorised)
    }

    func testScannerPreservesAUTypeWithoutExecutingPlugin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["AudioComponents": [["name": "Fixture", "type": "aumu"]]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let record = BundleMetadataReader().read(bundleURL: root, format: .audioUnit)
        XCTAssertEqual(PluginCategory.classify(evidence: record.evidence), .instrument)
        XCTAssertNil(record.executablePath)
        XCTAssertTrue(record.evidence.contains { $0.field == "AudioComponents[0].type" && $0.value == "aumu" })
    }

    func testVST3OnlyUsesAudioClassesAndHandlesMalformedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        for subcategories: Any in [["Fx", "EQ"], "Fx|EQ", 42] {
            let data: [String: Any] = ["Classes": [
                ["Category": "Component Controller Class", "Sub Categories": ["Instrument"]],
                ["Category": "Audio Module Class", "Sub Categories": subcategories]
            ]]
            try JSONSerialization.data(withJSONObject: data).write(to: root.appendingPathComponent("Contents/Resources/moduleinfo.json"))
            let record = BundleMetadataReader().read(bundleURL: root, format: .vst3)
            XCTAssertEqual(PluginCategory.classify(evidence: record.evidence), subcategories is Int ? .uncategorised : .audioEffect)
        }
    }
}
