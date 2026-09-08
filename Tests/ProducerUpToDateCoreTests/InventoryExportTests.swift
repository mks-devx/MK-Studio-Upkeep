// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class InventoryExportTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/opt/fixture-home")
    private func bundle(_ name: String, version: String, path: String) -> PluginBundleRecord {
        PluginBundleRecord(id: name + version, name: name, vendor: "Vendor, Inc.", format: .vst3, bundleIdentifier: "com.vendor.\(name.lowercased())",
            displayVersion: version, buildVersion: nil, path: URL(fileURLWithPath: path), executablePath: nil, architectures: [.x86_64],
            fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
    }
    private func product(_ name: String, version: String, path: String) -> NormalizedPluginProduct {
        NormalizedPluginProduct(id: name, name: name, vendor: "Vendor, Inc.", bundles: [bundle(name, version: version, path: path)],
                                confidence: .high, matchEvidence: [], requiresVerification: false)
    }

    func testCSVEscapesQuotesAndCommasAndHidesTheHomeFolder() {
        let result = PluginUpdateResult(product: product("Comp \"Pro\"", version: "1.2", path: "/opt/fixture-home/Library/Audio/Plug-Ins/VST3/Comp.vst3"),
                                        updateState: .notChecked, reason: .noReviewedRelease)
        let rows = InventoryExport.rows(plugins: [result], daws: [], homeDirectory: home)
        XCTAssertEqual(rows.first?.paths, ["~/Library/Audio/Plug-Ins/VST3/Comp.vst3"])
        let csv = InventoryExport.csv(rows, includePaths: true)
        XCTAssertTrue(csv.hasPrefix("Type,Name,Vendor,Installed version,Formats,Architecture,Update result,Latest reviewed version,Why not checked,Paths\n"))
        XCTAssertTrue(csv.contains("\"Comp \"\"Pro\"\"\",\"Vendor, Inc.\",1.2,VST3,Intel,Not in catalogue,,Not in the catalogue yet,~/Library"))
        XCTAssertFalse(csv.contains("/opt/fixture-home"), "The account folder never appears")
        XCTAssertFalse(InventoryExport.csv(rows, includePaths: false).contains("Library/Audio"), "Paths are opt-in")
    }

    func testTextExportListsPluginsAndDAWsAndStatesLocality() {
        let daw = InstalledDAWRecord(id: "live", definitionID: "ableton-live", name: "Live", vendor: "Ableton", bundleIdentifier: "com.ableton.live",
                                     displayVersion: "12.4", buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Live.app"), executablePath: nil, architectures: [.arm64])
        let rows = InventoryExport.rows(plugins: [PluginUpdateResult(product: product("Verb", version: "2.0", path: "/Library/Audio/Plug-Ins/VST3/Verb.vst3"), updateState: .current, latestVersion: "2.0")],
                                        daws: [daw], homeDirectory: home)
        let text = InventoryExport.text(rows, includePaths: false, exportedOn: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(text.contains("1 plugin products · 1 DAWs"))
        XCTAssertTrue(text.contains("nothing was sent anywhere"))
        XCTAssertTrue(text.contains("DAW: Live — Ableton · 12.4 · Apple Silicon · Not checked"))
        XCTAssertTrue(text.contains("Plugin: Verb — Vendor, Inc. · 2.0 · VST3 · Intel · Matches listed version (reviewed: 2.0)"))
    }

    func testScanComparisonFindsAddedRemovedAndChangedVersions() throws {
        let before = ScanSnapshot(finishedAt: Date(timeIntervalSince1970: 100), products: [product("A", version: "1.0", path: "/x"), product("B", version: "1.0", path: "/y")])
        let after = ScanSnapshot(finishedAt: Date(timeIntervalSince1970: 200), products: [product("B", version: "1.1", path: "/y"), product("C", version: "3.0", path: "/z")])
        let comparison = ScanComparison(previous: before, current: after)
        XCTAssertEqual(comparison.added.map(\.entry.name), ["C"])
        XCTAssertEqual(comparison.removed.map(\.entry.name), ["A"])
        XCTAssertEqual(comparison.changed.map { "\($0.entry.name) \($0.previousVersion ?? "") → \($0.entry.version)" }, ["B 1.0 → 1.1"])
        XCTAssertTrue(ScanComparison(previous: before, current: before).isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("last-scan.json")
        try after.save(to: url)
        XCTAssertEqual(ScanSnapshot.load(from: url), after)
        try Data(String(repeating: "[", count: 40).utf8).write(to: url)
        XCTAssertNil(ScanSnapshot.load(from: url), "A hostile or broken snapshot is ignored, never trusted")
    }
    func testCSVQuotesCarriageReturnsInOptionalPaths() {
        let row = InventoryExport.Row(kind: "Plugin", name: "Fixture", vendor: "Example", installedVersion: "1.0",
            formats: "VST3", architectures: "Intel", result: "Website not identified", latestReviewed: "", reason: "",
            paths: ["/Library/Audio/Plug-Ins/VST3/Fixture\rCopy.vst3"])
        let csv = InventoryExport.csv([row], includePaths: true, localOnly: true)
        XCTAssertTrue(csv.contains("\"/Library/Audio/Plug-Ins/VST3/Fixture\rCopy.vst3\""))
    }

    func testLegacySnapshotCannotCreateFalseChangesAfterIdentityMigration() throws {
        let snapshot = ScanSnapshot(finishedAt: Date(), products: [], scopeID: "fixture")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.json")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        old.removeValue(forKey: "identitySchemaVersion")
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let loaded = try XCTUnwrap(ScanSnapshot.load(from: url))
        XCTAssertFalse(loaded.canCompare(to: snapshot))
        XCTAssertTrue(snapshot.canCompare(to: snapshot))
    }

}
