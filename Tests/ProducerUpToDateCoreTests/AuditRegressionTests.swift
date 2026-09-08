// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class AuditRegressionTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testLargeBundlePreviewExceedsTheOldTwentyThousandEntryLimit() throws {
        let url = try root(); defer { try? FileManager.default.removeItem(at: url) }
        for index in 0..<20_010 {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("entry-\(index)"), withIntermediateDirectories: false)
        }
        let preview = try BundleContentsPreview.scan(url)
        XCTAssertEqual(preview.paths.count, 20_010)
        XCTAssertThrowsError(try BundleContentsPreview.scan(url, limit: 100))
    }
    func testRetiredOnlineRoutesStayDisabled() {
        func daw(_ version: String, inferred: Bool = false) -> InstalledDAWRecord {
            InstalledDAWRecord(id: "fixture", definitionID: "ableton-live", name: "Example DAW", vendor: "Example",
                bundleIdentifier: "com.example.host", displayVersion: version, buildVersion: nil,
                path: URL(fileURLWithPath: "/Applications/Example.app"), executablePath: nil, architectures: [.arm64], identityIsInferred: inferred)
        }
        XCTAssertNil(DAWUpdateSource.checker(for: daw("12.0")))
        XCTAssertNil(DAWUpdateSource.checker(for: daw("13.0")))
        XCTAssertNil(DAWUpdateSource.checker(for: daw("12.0", inferred: true)))
    }
    func testMetadataReadsRefuseFIFOsAndLinks() throws {
        let url = try root(); defer { try? FileManager.default.removeItem(at: url) }
        let fifo = url.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertNil(SafeFileAccess.data(at: fifo))
        let file = url.appendingPathComponent("regular")
        try Data("metadata".utf8).write(to: file)
        let link = url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertNil(SafeFileAccess.data(at: link))
        XCTAssertEqual(SafeFileAccess.data(at: file), Data("metadata".utf8))
    }
    func testVisibilityNeverHidesBothEntryPoints() {
        XCTAssertTrue(AppVisibility(dock: false, menuBar: false).dock)
        XCTAssertEqual(AppVisibility(dock: false, menuBar: true), AppVisibility(dock: false, menuBar: true))
        XCTAssertFalse(AppVisibility(dock: false, menuBar: true).dock)
    }
    func testCSVTreatsUntrustedFormulaPrefixesAsText() {
        for name in ["=1+1", "+1+1", "-1+1", "@SUM(A1)", "\t=1+1"] {
            let row = InventoryExport.Row(kind: "Plugin", name: name, vendor: "Example", installedVersion: "1.0", formats: "AU", architectures: "Intel", result: "Not checked", latestReviewed: "", reason: "", paths: [])
            XCTAssertTrue(InventoryExport.csv([row], includePaths: false).contains("Plugin,'" + name + ","))
        }
    }
    func testSnapshotsRequireSameKnownScope() {
        let a = ScanSnapshot(finishedAt: Date(), products: [], scopeID: "scope-a")
        XCTAssertFalse(a.canCompare(to: ScanSnapshot(finishedAt: Date(), products: [], scopeID: "scope-b")))
        XCTAssertFalse(a.canCompare(to: ScanSnapshot(finishedAt: Date(), products: [])))
        XCTAssertTrue(a.canCompare(to: ScanSnapshot(finishedAt: Date(), products: [], scopeID: "scope-a")))
    }
    func testStorageCountsHiddenFilesOnceAndNeverFollowsLinks() throws {
        let url = try root(); defer { try? FileManager.default.removeItem(at: url) }
        let bundle = url.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let file = bundle.appendingPathComponent(".hidden")
        try Data(repeating: 0, count: 123).write(to: file)
        try FileManager.default.linkItem(at: file, to: bundle.appendingPathComponent("hardlink"))
        try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("outside"), withDestinationURL: url)
        let result = try StorageMeasurement.measure([bundle, bundle])
        XCTAssertEqual(result.bytes, 123)
        XCTAssertFalse(result.incomplete)
        XCTAssertTrue(try StorageMeasurement.measure([bundle], limit: 0).incomplete)
        XCTAssertTrue(try StorageMeasurement.measure([url.appendingPathComponent("Missing.app")]).incomplete)
    }
    func testStorageCancellation() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try StorageMeasurement.measure([])
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
    }
    func testDeepDiscoverySelectsOnlyExactSoftwareAndPreservesSupportData() throws {
        let url = try root(); defer { try? FileManager.default.removeItem(at: url) }
        func bundle(_ name: String, _ id: String) throws -> URL {
            let path = url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0).write(to: path.appendingPathComponent("Contents/Info.plist"))
            return path
        }
        let first = try bundle("Example.vst3", "com.example.product")
        let copy = try bundle(".Copy.component", "com.example.product")
        _ = try bundle("Unrelated.vst3", "com.example.product.other")
        let support = url.appendingPathComponent("com.example.product.plist")
        try Data("user settings and licence".utf8).write(to: support)
        let item = CleanupItem(path: first, kind: .pluginBundle)
        let original = CleanupPlan(displayName: "Example", items: [item], excludedUserContentDescription: "Preserve support data")
        let report = try UninstallDiscovery.scan(identifiers: ["com.example.product"], roots: [url])
        let extra = UninstallDiscovery.additionalSoftware(in: report, original: original, safety: CleanupSafety(allowedRoots: [url]))
        XCTAssertEqual(extra.map { $0.path.resolvingSymlinksInPath().path }, [copy.resolvingSymlinksInPath().path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.path))
        XCTAssertFalse(extra.contains { $0.path == support })
        let empty = CleanupPlan(displayName: "Unknown", items: [], excludedUserContentDescription: "")
        XCTAssertTrue(UninstallDiscovery.additionalSoftware(in: report, original: empty, safety: CleanupSafety(allowedRoots: [url])).isEmpty)
    }
    func testDeepScanUsesRequestedHomeAndReportsDepthLimits() throws {
        let url = try root(); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(UninstallDiscovery.roots(homeDirectory: url).contains(url.appendingPathComponent("Library/Containers")))
        try FileManager.default.createDirectory(at: url.appendingPathComponent("a/b/c"), withIntermediateDirectories: true)
        let report = try UninstallDiscovery.scan(identifiers: ["com.example.product"], roots: [url], maximumDepth: 1)
        XCTAssertTrue(report.warnings.contains { $0.contains("incomplete") })
    }

}
