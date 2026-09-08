// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class PreservedSettingsTests: XCTestCase {
    func testRelatedDataCannotEnterRemovalEvenWhenExplicitlyPlanned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("org.example.fixture.plist")
        try Data("preserved fixture".utf8).write(to: file)
        for kind in [CleanupItemKind.preferences, .cache, .applicationSupport, .savedState] {
            var moves = 0
            let plan = CleanupPlan(displayName: "Fixture", items: [.init(path: file, kind: kind)], excludedUserContentDescription: "")
            let result = CleanupExecutor.execute(plan, safety: CleanupSafety(allowedRoots: [root])) { _ in moves += 1 }
            XCTAssertEqual(moves, 0)
            XCTAssertFalse(result.failures.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }
}
