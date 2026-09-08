// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class ScannerRobustnessTests: XCTestCase {
    func testCancellationReachesAnAlreadyRunningWorker() async throws {
        let state = WorkerState()
        let task = Task {
            try await CancellableWorker.run {
                state.markStarted()
                defer { state.markStopped() }
                while true { try Task.checkCancellation(); Thread.sleep(forTimeInterval: 0.001) }
            }
        }
        let deadline = Date().addingTimeInterval(2)
        while !state.started && Date() < deadline { await Task.yield() }
        XCTAssertTrue(state.started)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled operation completed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(state.stopped)
    }

    func testMalformedOversizedAndEscapingMetadata() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fixture.component")
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: info)
        XCTAssertTrue(BundleMetadataReader().read(bundleURL: bundle, format: .audioUnit).issues.contains { $0.id == "missing-info-plist" })
        try Data(repeating: 32, count: 4_194_305).write(to: info)
        XCTAssertNil(SafeFileAccess.data(at: info))
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "../../../outside", "CFBundleShortVersionString": ["bad"]], format: .xml, options: 0)
        try data.write(to: info)
        let record = BundleMetadataReader().read(bundleURL: bundle, format: .audioUnit)
        XCTAssertNil(record.executablePath)
        XCTAssertNil(record.displayVersion)
        let outside = root.appendingPathComponent("outside")
        try Data([0xcf,0xfa,0xed,0xfe,12,0,0,1]).write(to: outside)
        let binary = bundle.appendingPathComponent("Contents/MacOS/Binary")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: outside)
        XCTAssertNil(SafeFileAccess.executable(in: bundle, name: "Binary"))
    }

    func testLargeInventoryDeduplicationAndNormalization() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<2_000 {
            let url = root.appendingPathComponent("Vendor/Fixture\(index).vst3/Contents")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.fixture.p\(index)", "CFBundleName": "Fixture \(index)", "CFBundleShortVersionString": "1.0"], format: .binary, options: 0)
            try data.write(to: url.appendingPathComponent("Info.plist"))
        }
        let location = ScanLocation(url: root, format: .vst3)
        let start = Date()
        let report = try PluginScanner().scan(configuration: ScanConfiguration(locations: [location, location]))
        let products = try ProductNormalizer().normalizeCancellable(records: report.records)
        XCTAssertEqual(report.records.count, 2_000)
        XCTAssertEqual(products.products.count, 2_000)
        XCTAssertEqual(products.products.flatMap(\.bundles).count, 2_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 30, "2,000 bundle scan and normalization exceeded the beta budget")
    }

    func testCancelledPipelineDoesNotReturnSuccess() async throws {
        let task = Task {
            try await ScanPipeline.run(configuration: ScanConfiguration(locations: []), scanDAWs: false)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled worker returned success") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testTruncatedFatMachODoesNotClaimArchitecture() {
        let truncated = Data([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 2, 1, 0, 0, 12])
        XCTAssertTrue(MachOArchitectureDetector.architectures(in: truncated).isEmpty)
    }
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class WorkerState: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    private var didStop = false
    var started: Bool { lock.withLock { didStart } }
    var stopped: Bool { lock.withLock { didStop } }
    func markStarted() { lock.withLock { didStart = true } }
    func markStopped() { lock.withLock { didStop = true } }
}
