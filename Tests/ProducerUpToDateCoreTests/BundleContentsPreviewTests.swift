// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class BundleContentsPreviewTests: XCTestCase {
    func testHiddenContentsLinksAndChangedContentsInvalidateRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fixture.vst3")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.vendor.fixture"], format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let hidden = bundle.appendingPathComponent("Contents/.hidden")
        try Data("original".utf8).write(to: hidden)
        try FileManager.default.createSymbolicLink(at: bundle.appendingPathComponent("outside"), withDestinationURL: root)
        let snapshot = try BundleContentsPreview.scan(bundle)
        XCTAssertTrue(snapshot.paths.contains("Contents/.hidden"))
        XCTAssertTrue(snapshot.paths.contains("outside"))
        XCTAssertFalse(snapshot.paths.contains { $0.hasPrefix("outside/") })
        XCTAssertThrowsError(try BundleContentsPreview.scan(bundle, limit: 1))
        let item = CleanupItem(path: bundle, kind: .pluginBundle, contentsFingerprint: snapshot.fingerprint)
        let safety = CleanupSafety(allowedRoots: [root])
        XCTAssertNil(safety.validate(item))
        try Data("changed and longer".utf8).write(to: hidden)
        XCTAssertNotNil(safety.validate(item))
        var moves = 0
        let result = CleanupExecutor.execute(.init(displayName: "Fixture", items: [item], excludedUserContentDescription: ""), safety: safety) { _ in moves += 1 }
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(moves, 0)
    }
}
