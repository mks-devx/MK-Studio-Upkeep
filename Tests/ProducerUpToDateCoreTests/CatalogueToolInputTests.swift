// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

/// Exercises the offline executable reader itself; no live inventory or network input.
final class CatalogueToolInputTests: XCTestCase {
    private func run(registry: URL, inventory: URL, feeds: URL) throws -> Int32 {
        let directory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let binary = directory.appendingPathComponent("CatalogueTool")
        // SwiftPM builds the executable beside the test bundle.
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            XCTFail("CatalogueTool must be built beside the test bundle")
            return -1
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--prototype-updates", registry.path, inventory.path, feeds.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            XCTFail("Offline input reader blocked instead of rejecting the file")
            return -1
        }
        return process.terminationStatus
    }

    func testOfflineInputsRejectLinksPipesOversizeAndDeepJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = root.appendingPathComponent("registry.json")
        let inventory = root.appendingPathComponent("inventory.json")
        let feeds = root.appendingPathComponent("feeds.json")
        let valid = Data(#"{"products":[],"sources":[]}"#.utf8)
        try valid.write(to: registry)
        try Data("[]".utf8).write(to: inventory)
        try Data("{}".utf8).write(to: feeds)
        XCTAssertEqual(try run(registry: registry, inventory: inventory, feeds: feeds), 0)
        let link = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: registry)
        XCTAssertEqual(try run(registry: link, inventory: inventory, feeds: feeds), 1)
        let pipe = root.appendingPathComponent("pipe.json")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        XCTAssertEqual(try run(registry: pipe, inventory: inventory, feeds: feeds), 1)
        let deep = #"{"products":[],"sources":[],"unused":"# + String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40) + "}"
        try Data(deep.utf8).write(to: registry)
        XCTAssertEqual(try run(registry: registry, inventory: inventory, feeds: feeds), 1)
        try (valid + Data(repeating: 0x20, count: GeneralUpdateEngine.maximumBytes)).write(to: registry)
        XCTAssertEqual(try run(registry: registry, inventory: inventory, feeds: feeds), 1)
    }
}
