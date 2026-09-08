// SPDX-License-Identifier: BUSL-1.1
import Foundation
import Darwin
import XCTest
@testable import ProducerUpToDateCore

final class ReleaseAuditTests: XCTestCase {
    func testModifiedSignedExecutableIsNotTrusted() throws {
        let original = URL(fileURLWithPath: "/bin/echo")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let copy = root.appendingPathComponent("fixture")
        try FileManager.default.copyItem(at: original, to: copy)
        XCTAssertEqual(BundleProvenance.read(at: copy).signature, .apple)
        var data = try Data(contentsOf: copy)
        XCTAssertGreaterThan(data.count, 8192)
        data[8192] ^= 1
        try data.write(to: copy)
        XCTAssertEqual(BundleProvenance.read(at: copy).signature, .invalid)
    }

    func testArchitectureReaderRejectsFIFOAndLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fifo = root.appendingPathComponent("pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertTrue(MachOArchitectureDetector.architectures(at: fifo).isEmpty)
        let file = root.appendingPathComponent("header")
        try (Data([0xcf, 0xfa, 0xed, 0xfe, 0x07, 0, 0, 1]) + Data(repeating: 0, count: 24)).write(to: file)
        XCTAssertEqual(MachOArchitectureDetector.architectures(at: file), [.x86_64])
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertTrue(MachOArchitectureDetector.architectures(at: link).isEmpty)
    }

    func testDepthLimitIsIncompleteForPluginsAndDAWs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var nested = root
        for _ in 0..<10 { nested.appendPathComponent("nested") }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let plugins = try PluginScanner().scan(configuration: .init(locations: [.init(url: root, format: .vst3)]))
        XCTAssertGreaterThan(plugins.inaccessibleLocationCount, 0)
        let daws = try DAWScanner().scanReport(configuration: .init(applicationRoots: [root], definitions: DAWScanConfiguration.standard.definitions))
        XCTAssertTrue(daws.scopeNotes.contains { $0.contains("exceeds the application search depth") })
        XCTAssertTrue(daws.warnings.isEmpty)
        var skipped = root
        for _ in 0...DAWScanner.maximumDepth { skipped.appendPathComponent("nested") }
        XCTAssertTrue(daws.scopeNotes.contains { $0.contains(skipped.path) })
        XCTAssertTrue(daws.scopeNotes.contains { $0.contains("same scan again will not extend it") })
    }

    func testSnapshotRejectsDuplicateIDsAndDisplayControls() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("snapshot.json")
        let entry: [String: Any] = ["id": "fixture", "name": "Fixture", "vendor": "Example", "version": "1"]
        func write(_ entries: [[String: Any]]) throws {
            try JSONSerialization.data(withJSONObject: ["scopeID": "fixture", "finishedAt": 0, "entries": entries]).write(to: url)
        }
        try write([entry])
        XCTAssertNotNil(ScanSnapshot.load(from: url))
        try write([entry, entry])
        XCTAssertNil(ScanSnapshot.load(from: url))
        var hostile = entry
        hostile["name"] = "Fixture" + String(UnicodeScalar(0x202E)!)
        try write([hostile])
        XCTAssertNil(ScanSnapshot.load(from: url))
    }
}
