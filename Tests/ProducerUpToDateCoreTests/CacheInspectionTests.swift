// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class CacheInspectionTests: XCTestCase {
    private func daw(_ id: String, inferred: Bool = false) -> InstalledDAWRecord {
        .init(id: id, definitionID: "fixture", name: "Fixture DAW", vendor: "Example", bundleIdentifier: id,
              displayVersion: "1", buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Fixture.app"),
              executablePath: nil, architectures: [], identityIsInferred: inferred)
    }
    func testScopeRejectsInferredIdentitiesTraversalAndDuplicates() {
        let locations = CacheInspection.locations(daws: [daw("org.example.audio"), daw("org.example.audio"),
            daw("../../Projects"), daw("org.example.unknown", inferred: true)], home: URL(fileURLWithPath: "/fixture"))
        XCTAssertEqual(locations.count, 3)
        XCTAssertTrue(locations.allSatisfy { $0.path.path.contains("/Library/Caches/") })
        XCTAssertFalse(locations.contains { $0.path.path.contains("Projects") || $0.path.path.contains("unknown") })
    }
    func testReadOnlySizesSkipLinksAndDoNotVisitOtherFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Library/Caches/AudioUnitCache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let data = Data(repeating: 3, count: 20)
        let file = cache.appendingPathComponent(".fixture")
        try data.write(to: file)
        let outside = root.appendingPathComponent("Project.fixture")
        try Data(repeating: 4, count: 100).write(to: outside)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("linked"), withDestinationURL: outside)
        let locations = CacheInspection.locations(daws: [], home: root)
        let report = try CacheInspection.inspect(locations)
        XCTAssertEqual(report.entries.first?.measurement.bytes, 20)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try CacheInspection.inspect(locations, limit: 0).skipped, 1)
    }
    func testMissingIsNotReportedAsZeroAndLinkedRootIsSkipped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = CacheInspection.locations(daws: [], home: root)
        XCTAssertTrue(try CacheInspection.inspect(locations).entries.isEmpty)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: locations[0].path, withDestinationURL: root)
        let report = try CacheInspection.inspect(locations)
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertEqual(report.skipped, 1)
    }
    func testVendorLocationsRequireRecognisedIdentityAndPreserveDatabases() {
        let paths = CacheInspection.locations(daws: [
            daw("com.bitwig.BitwigStudio"), daw("se.propellerheads.reason"),
            daw("com.image-line.flstudio"), daw("com.native-instruments.Maschine 3")
        ], home: URL(fileURLWithPath: "/fixture")).map { $0.path.path }
        XCTAssertTrue(paths.contains("/fixture/Library/Application Support/Bitwig/Bitwig Studio/index"))
        XCTAssertTrue(paths.contains("/fixture/Library/Application Support/Propellerhead Software/Reason/Caches"))
        XCTAssertTrue(paths.contains("/fixture/Library/Caches/com.native-instruments.Maschine 3"))
        XCTAssertFalse(paths.contains { $0.contains("/Documents/") || $0.contains("/Application Support/Native Instruments/") })
        let inferred = CacheInspection.locations(daws: [daw("com.bitwig.BitwigStudio", inferred: true)])
        XCTAssertEqual(inferred.count, 1)
    }
    func testCancellationStopsInspection() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CacheInspection.inspect(CacheInspection.locations(daws: []))
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
