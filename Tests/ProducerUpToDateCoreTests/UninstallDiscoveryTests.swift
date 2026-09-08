// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class UninstallDiscoveryTests: XCTestCase {
    func testExactHiddenMatchesPreservedAndSharedNamesNotGuessed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let names = ["com.vendor.product.plist", ".com.vendor.product", "com.vendor.other.plist", "Product Presets", "com.vendor.product2.plist"]
        for name in names { try Data("licence or user data".utf8).write(to: root.appendingPathComponent(name)) }
        let report = try UninstallDiscovery.scan(identifiers: ["com.vendor.product"], roots: [root])
        XCTAssertEqual(Set(report.findings.map { $0.path.lastPathComponent }), ["com.vendor.product.plist", ".com.vendor.product"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, names.count)
        XCTAssertTrue(report.findings.allSatisfy { $0.evidence.contains("Preserved") })
        XCTAssertTrue(try UninstallDiscovery.scan(identifiers: ["../../Music"], roots: [root]).findings.isEmpty)
    }

    func testLinksAndBoundedInventories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("com.vendor.product"), withDestinationURL: root)
        XCTAssertTrue(try UninstallDiscovery.scan(identifiers: ["com.vendor.product"], roots: [root]).findings.isEmpty)
        let limited = try UninstallDiscovery.scan(identifiers: ["com.vendor.product"], roots: [root], limit: 0)
        XCTAssertEqual(limited.inspectedEntries, 0)
        XCTAssertTrue(limited.warnings.contains { $0.contains("incomplete") })
    }

    func testCancellation() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try UninstallDiscovery.scan(identifiers: ["com.vendor.product"], roots: [])
        }
        do { _ = try await task.value; XCTFail("Cancelled discovery completed") }
        catch is CancellationError { }
    }

    func testHiddenPluginCopyUsesExactMetadataIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent(".Hidden.vst3")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.vendor.product"], format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let report = try UninstallDiscovery.scan(identifiers: ["com.vendor.product"], roots: [root])
        XCTAssertEqual(report.findings.map { $0.path.resolvingSymlinksInPath().path }, [bundle.resolvingSymlinksInPath().path])
        XCTAssertTrue(try UninstallDiscovery.scan(identifiers: ["com.vendor.product2"], roots: [root]).findings.isEmpty)
    }

    func testHoldRequiresFiveSecondsAndNeverAcceptsCancellationOrInvalidTime() {
        XCTAssertFalse(HoldToConfirmPolicy.permits(start: 100, end: 104.999, cancelled: false))
        XCTAssertTrue(HoldToConfirmPolicy.permits(start: 100, end: 105, cancelled: false))
        XCTAssertFalse(HoldToConfirmPolicy.permits(start: 100, end: 110, cancelled: true))
        XCTAssertFalse(HoldToConfirmPolicy.permits(start: 100, end: 99, cancelled: false))
        XCTAssertFalse(HoldToConfirmPolicy.permits(start: 100, end: .infinity, cancelled: false))
    }
}
