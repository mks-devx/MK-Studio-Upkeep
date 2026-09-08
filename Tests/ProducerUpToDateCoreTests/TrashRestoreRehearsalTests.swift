// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class TrashRestoreRehearsalTests: XCTestCase {
    func testSyntheticBundlesCanBeTrashedAndRestoredWithoutChangingNeighbours() throws {
        guard ProcessInfo.processInfo.environment["STUDIO_UPKEEP_TRASH_REHEARSAL"] == "1" else {
            throw XCTSkip("Opt-in real Trash rehearsal using disposable synthetic bundles only.")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("upkeep-rehearsal-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Only this test's synthetic root is cleaned up. Nothing else in Trash is inspected.
        defer { try? fm.removeItem(at: root) }
        let sentinel = Data("synthetic project, settings and licence content".utf8)
        let neighbours = ["Project.als", "Settings.plist", "Licence.txt"].map { root.appendingPathComponent($0) }
        for url in neighbours { try sentinel.write(to: url) }
        for ext in ["component", "vst3", "app"] {
            let bundle = root.appendingPathComponent("Fixture-" + UUID().uuidString + "." + ext)
            let contents = bundle.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let metadata = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.rehearsal", "CFBundleVersion": "1"], format: .xml, options: 0)
            try metadata.write(to: contents.appendingPathComponent("Info.plist"))
            let payload = contents.appendingPathComponent("SyntheticPayload")
            try sentinel.write(to: payload)
            let preview = try BundleContentsPreview.scan(bundle)
            let item = CleanupItem(path: bundle, kind: ext == "app" ? .application : .pluginBundle, contentsFingerprint: preview.fingerprint)
            let plan = CleanupPlan(displayName: "Synthetic fixture", items: [item], excludedUserContentDescription: "Neighbours preserved")
            var trashed: NSURL?
            defer {
                if let url = trashed as URL?, !fm.fileExists(atPath: bundle.path) { try? fm.moveItem(at: url, to: bundle) }
            }
            let result = CleanupExecutor.execute(plan, safety: CleanupSafety(allowedRoots: [root])) { url in
                try fm.trashItem(at: url, resultingItemURL: &trashed)
            }
            XCTAssertEqual(result.movedCount, 1, result.failures.joined(separator: "; "))
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertFalse(fm.fileExists(atPath: bundle.path))
            let trashURL = try XCTUnwrap(trashed as URL?)
            try fm.moveItem(at: trashURL, to: bundle)
            XCTAssertEqual(try Data(contentsOf: payload), sentinel)
            XCTAssertEqual(try Data(contentsOf: contents.appendingPathComponent("Info.plist")), metadata)
            for url in neighbours { XCTAssertEqual(try Data(contentsOf: url), sentinel) }
        }
    }
}
