// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class RemovalBackupTests: XCTestCase {
    private let fm = FileManager.default

    func testDamagedRecordDoesNotHideHealthyBackupOrBlockRetention() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let store = RemovalBackupStore(root: fixture.backups, now: { Date(timeIntervalSince1970: 1_000) })
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Fixture.component"), payload: "recover")
        let safety = CleanupSafety(allowedRoots: [fixture.source])
        let good = try await store.prepare(plan: plan("Good", bundle), safety: safety, retentionDays: 1)
        let bad = try await store.prepare(plan: plan("Bad", bundle), safety: safety, retentionDays: 1)
        let damaged = fixture.backups.appendingPathComponent(bad.id.uuidString)
        try Data("{".utf8).write(to: damaged.appendingPathComponent("manifest.json"))
        let records = try await store.list()
        XCTAssertEqual(records.map(\.id), [good.id])
        try fm.removeItem(at: bundle)
        _ = try await store.restore(operationID: good.id, itemID: good.items[0].id, safety: safety)
        XCTAssertTrue(fm.fileExists(atPath: bundle.path))
        let expired = RemovalBackupStore(root: fixture.backups, now: { Date(timeIntervalSince1970: 100_000) })
        let deleted = try await expired.deleteExpired()
        XCTAssertEqual(deleted.operationCount, 1)
        XCTAssertTrue(fm.fileExists(atPath: damaged.path), "Unreadable recovery data must stay intact")
    }

    func testOverflowingStoredSizeIsReportedAndPreserved() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let store = RemovalBackupStore(root: fixture.backups)
        let first = try makeBundle(fixture.source.appendingPathComponent("One.component"), payload: "one")
        let second = try makeBundle(fixture.source.appendingPathComponent("Two.component"), payload: "two")
        let operation = try await store.prepare(plan: CleanupPlan(displayName: "Fixture", items: [
            CleanupItem(path: first, kind: .pluginBundle), CleanupItem(path: second, kind: .pluginBundle)
        ], excludedUserContentDescription: "Preserved"), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
        let record = fixture.backups.appendingPathComponent(operation.id.uuidString).appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
        var items = try XCTUnwrap(object["items"] as? [[String: Any]])
        items[0]["byteCount"] = Int64.max
        items[1]["byteCount"] = 1
        object["items"] = items
        try JSONSerialization.data(withJSONObject: object).write(to: record)
        let listing = try await store.inspect()
        XCTAssertEqual(listing.unreadableCount, 1)
        XCTAssertTrue(listing.records.isEmpty)
        let deletion = try await store.deleteAll()
        XCTAssertEqual(deletion.operationCount, 0)
        XCTAssertTrue(fm.fileExists(atPath: record.path))
    }

    func testOversizedManifestTotalDoesNotTrap() {
        let item = RemovalBackupItem(id: UUID(), originalPath: "/Applications/Fixture.app", kind: .application,
            payloadRelativePath: "Payload/fixture", byteCount: Int64.max, contentFingerprint: "fixture")
        let manifest = RemovalBackupManifest(schemaVersion: 1, id: UUID(), displayName: "Fixture",
            createdAt: Date(), expiresAt: Date(), items: [item, item])
        XCTAssertEqual(manifest.byteCount, Int64.max)
    }

    func testPreferencesDefaultToBackupAndThirtyDayAutomaticRetention() {
        let suite = "RemovalBackupTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = RemovalBackupPreferences(defaults: defaults)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertTrue(preferences.automaticallyDeletesExpired)
        XCTAssertEqual(preferences.retentionDays, 30)
    }

    func testPrepareCopiesAndVerifiesEveryItemBeforeCommittingHistory() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let first = try makeBundle(fixture.source.appendingPathComponent("First.component"), payload: "one")
        let second = try makeBundle(fixture.source.appendingPathComponent("Second.vst3"), payload: "two")
        let plan = CleanupPlan(displayName: "Fixture Suite", items: [
            CleanupItem(path: first, kind: .pluginBundle, contentsFingerprint: try BundleContentsPreview.scan(first).fingerprint),
            CleanupItem(path: second, kind: .pluginBundle, contentsFingerprint: try BundleContentsPreview.scan(second).fingerprint)
        ], excludedUserContentDescription: "Preserved")
        let store = RemovalBackupStore(root: fixture.backups, now: { Date(timeIntervalSince1970: 1_000) })

        let operation = try await store.prepare(plan: plan, safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)

        XCTAssertEqual(operation.displayName, "Fixture Suite")
        XCTAssertEqual(operation.items.count, 2)
        XCTAssertEqual(operation.expiresAt, Date(timeIntervalSince1970: 1_000 + 30 * 86_400))
        let listed = try await store.list()
        XCTAssertEqual(listed.map(\.id), [operation.id])
        for item in operation.items {
            XCTAssertTrue(fm.fileExists(atPath: fixture.backups.appendingPathComponent(operation.id.uuidString).appendingPathComponent(item.payloadRelativePath).path))
            XCTAssertEqual(item.state, .backedUp)
        }
        XCTAssertTrue(fm.fileExists(atPath: first.path))
        XCTAssertTrue(fm.fileExists(atPath: second.path))
    }

    func testBackupMetadataUsesPrivateFilesystemPermissions() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Private.component"), payload: "private")
        let store = RemovalBackupStore(root: fixture.backups)

        let operation = try await store.prepare(plan: plan("Private", bundle),
            safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)

        let operationDirectory = fixture.backups.appendingPathComponent(operation.id.uuidString)
        let manifest = operationDirectory.appendingPathComponent("manifest.json")
        XCTAssertEqual(permissions(of: fixture.backups), 0o700)
        XCTAssertEqual(permissions(of: operationDirectory), 0o700)
        XCTAssertEqual(permissions(of: manifest), 0o600)
    }

    func testPrepareRejectsSymbolicLinkBackupRoot() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let realBackups = fixture.root.appendingPathComponent("Real Backups")
        try fm.createDirectory(at: realBackups, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: fixture.backups, withDestinationURL: realBackups)
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Linked.component"), payload: "linked")
        let store = RemovalBackupStore(root: fixture.backups)

        do {
            _ = try await store.prepare(plan: plan("Linked", bundle),
                safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
            XCTFail("A symbolic-link backup root must be rejected")
        } catch let error as RemovalBackupError {
            XCTAssertEqual(error, .invalidBackupStorage)
        }
        XCTAssertTrue((try fm.contentsOfDirectory(atPath: realBackups.path)).isEmpty)
    }

    func testPrepareFailureLeavesNoCommittedOrStagingOperation() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Changed.component"), payload: "before")
        let item = CleanupItem(path: bundle, kind: .pluginBundle, contentsFingerprint: try BundleContentsPreview.scan(bundle).fingerprint)
        try Data("after".utf8).write(to: bundle.appendingPathComponent("Contents/Payload"))
        let store = RemovalBackupStore(root: fixture.backups)

        do {
            _ = try await store.prepare(plan: CleanupPlan(displayName: "Changed", items: [item], excludedUserContentDescription: ""), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
            XCTFail("Changed input must not be backed up")
        } catch { }

        let listed = try await store.list()
        XCTAssertTrue(listed.isEmpty)
        let names = (try? fm.contentsOfDirectory(atPath: fixture.backups.path)) ?? []
        XCTAssertTrue(names.isEmpty, names.joined(separator: ", "))
    }

    func testPrepareRejectsDuplicateAndUnboundedPlansBeforeCopying() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Repeated.component"), payload: "repeat")
        let item = try plan("Repeated", bundle).items[0]
        let store = RemovalBackupStore(root: fixture.backups)
        let safety = CleanupSafety(allowedRoots: [fixture.source])

        for items in [[item, item], Array(repeating: item, count: 1_001)] {
            do {
                _ = try await store.prepare(plan: CleanupPlan(displayName: "Repeated", items: items,
                    excludedUserContentDescription: ""), safety: safety, retentionDays: 30)
                XCTFail("Duplicate or unbounded plans must be refused")
            } catch { }
        }
        XCTAssertFalse(fm.fileExists(atPath: fixture.backups.path))
    }

    func testDeleteExpiredKeepsCurrentAndReturnsExactSummary() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let firstDate = Date(timeIntervalSince1970: 10_000)
        let firstStore = RemovalBackupStore(root: fixture.backups, now: { firstDate })
        let first = try makeBundle(fixture.source.appendingPathComponent("Old.component"), payload: "old")
        let old = try await firstStore.prepare(plan: plan("Old", first), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 7)
        let current = firstDate.addingTimeInterval(8 * 86_400)
        let store = RemovalBackupStore(root: fixture.backups, now: { current })
        let second = try makeBundle(fixture.source.appendingPathComponent("Current.component"), payload: "current")
        let recent = try await store.prepare(plan: plan("Current", second), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)

        let summary = try await store.deleteExpired()

        XCTAssertEqual(summary.operationCount, 1)
        XCTAssertGreaterThan(summary.byteCount, 0)
        let listed = try await store.list()
        XCTAssertEqual(Set(listed.map(\.id)), [recent.id])
        XCTAssertFalse(fm.fileExists(atPath: fixture.backups.appendingPathComponent(old.id.uuidString).path))
    }

    func testDeleteAllReturnsExactSummaryAndRemovesHistory() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let store = RemovalBackupStore(root: fixture.backups)
        let first = try makeBundle(fixture.source.appendingPathComponent("First.component"), payload: "first")
        let second = try makeBundle(fixture.source.appendingPathComponent("Second.component"), payload: "second")
        let firstBackup = try await store.prepare(plan: plan("First", first), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
        let secondBackup = try await store.prepare(plan: plan("Second", second), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)

        let summary = try await store.deleteAll()
        let remaining = try await store.list()

        XCTAssertEqual(summary.operationCount, 2)
        XCTAssertEqual(summary.byteCount, firstBackup.byteCount + secondBackup.byteCount)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRetentionCleanupRemovesOnlyAbandonedStagingDirectories() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        try fm.createDirectory(at: fixture.backups, withIntermediateDirectories: true)
        let abandoned = fixture.backups.appendingPathComponent(".staging-" + UUID().uuidString)
        let unrelated = fixture.backups.appendingPathComponent(".keep-this")
        try fm.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: abandoned.path)
        let store = RemovalBackupStore(root: fixture.backups, now: { Date(timeIntervalSince1970: 1_000 + 2 * 86_400) })

        _ = try await store.deleteExpired()

        XCTAssertFalse(fm.fileExists(atPath: abandoned.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
    }

    func testListRejectsManifestWithRelativeOriginalPath() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let store = RemovalBackupStore(root: fixture.backups)
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Unsafe.component"), payload: "unsafe")
        let operation = try await store.prepare(plan: plan("Unsafe", bundle), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
        let manifestURL = fixture.backups.appendingPathComponent(operation.id.uuidString).appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var items = try XCTUnwrap(object["items"] as? [[String: Any]])
        items[0]["originalPath"] = "../../unsafe.component"
        object["items"] = items
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        let listing = try await store.inspect()
        XCTAssertTrue(listing.records.isEmpty)
        XCTAssertEqual(listing.unreadableCount, 1)
        XCTAssertTrue(fm.fileExists(atPath: fixture.backups.appendingPathComponent(operation.id.uuidString).path))
    }

    func testListRejectsPayloadReplacedBySymbolicLink() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let store = RemovalBackupStore(root: fixture.backups)
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Linked.component"), payload: "linked")
        let operation = try await store.prepare(plan: plan("Linked", bundle), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
        let item = try XCTUnwrap(operation.items.first)
        let payload = fixture.backups.appendingPathComponent(operation.id.uuidString).appendingPathComponent(item.payloadRelativePath)
        try fm.removeItem(at: payload)
        try fm.createSymbolicLink(at: payload, withDestinationURL: bundle)

        let listing = try await store.inspect()
        XCTAssertTrue(listing.records.isEmpty)
        XCTAssertEqual(listing.unreadableCount, 1)
        XCTAssertTrue(fm.fileExists(atPath: fixture.backups.appendingPathComponent(operation.id.uuidString).path))
    }

    func testRestoreRefusesCollisionThenRestoresVerifiedPayload() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let bundle = try makeBundle(fixture.source.appendingPathComponent("Restore.component"), payload: "recover me")
        let store = RemovalBackupStore(root: fixture.backups)
        let operation = try await store.prepare(plan: plan("Restore", bundle), safety: CleanupSafety(allowedRoots: [fixture.source]), retentionDays: 30)
        let item = try XCTUnwrap(operation.items.first)

        do {
            _ = try await store.restore(operationID: operation.id, itemID: item.id, safety: CleanupSafety(allowedRoots: [fixture.source]))
            XCTFail("Restore must not replace an installed item")
        } catch let error as RemovalBackupError {
            XCTAssertEqual(error, .destinationOccupied)
        }

        try fm.removeItem(at: bundle)
        let restored = try await store.restore(operationID: operation.id, itemID: item.id, safety: CleanupSafety(allowedRoots: [fixture.source]))
        XCTAssertEqual(restored, bundle)
        XCTAssertEqual(try Data(contentsOf: bundle.appendingPathComponent("Contents/Payload")), Data("recover me".utf8))
        let listed = try await store.list()
        XCTAssertNotNil(listed.first?.items.first?.restoredAt)
    }

    func testProtectedCleanupNeverMovesWithoutBackupAndRecordsPartialRemoval() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        let changed = try makeBundle(fixture.source.appendingPathComponent("Changed.component"), payload: "before")
        let changedPlan = try plan("Changed", changed)
        try Data("after".utf8).write(to: changed.appendingPathComponent("Contents/Payload"))
        let store = RemovalBackupStore(root: fixture.backups)
        var attempted = 0

        let rejected = await BackupProtectedCleanupExecutor.execute(plan: changedPlan,
            safety: CleanupSafety(allowedRoots: [fixture.source]), store: store, retentionDays: 30) { _ in attempted += 1 }

        XCTAssertEqual(attempted, 0)
        XCTAssertEqual(rejected.cleanup.movedCount, 0)
        XCTAssertNil(rejected.backup)

        let first = try makeBundle(fixture.source.appendingPathComponent("First.component"), payload: "one")
        let second = try makeBundle(fixture.source.appendingPathComponent("Second.component"), payload: "two")
        let partialPlan = CleanupPlan(displayName: "Partial", items: [try plan("", first).items[0], try plan("", second).items[0]], excludedUserContentDescription: "")
        var movedPaths = Set<String>()
        let partial = await BackupProtectedCleanupExecutor.execute(plan: partialPlan,
            safety: CleanupSafety(allowedRoots: [fixture.source]), store: store, retentionDays: 30) { url in
                if !movedPaths.isEmpty { throw CocoaError(.fileWriteNoPermission) }
                movedPaths.insert(url.path)
            }

        XCTAssertEqual(partial.cleanup.movedCount, 1)
        XCTAssertEqual(partial.cleanup.failures.count, 1)
        XCTAssertEqual(partial.backup?.removedItemCount, 1)
        XCTAssertEqual(partial.backup?.items.first(where: { $0.originalPath == first.path })?.state, .removed)
        XCTAssertEqual(partial.backup?.items.first(where: { $0.originalPath == second.path })?.state, .backedUp)
    }

    private func plan(_ name: String, _ bundle: URL) throws -> CleanupPlan {
        CleanupPlan(displayName: name, items: [CleanupItem(path: bundle, kind: .pluginBundle,
            contentsFingerprint: try BundleContentsPreview.scan(bundle).fingerprint)], excludedUserContentDescription: "")
    }

    private func makeFixture() throws -> (root: URL, source: URL, backups: URL) {
        let root = fm.temporaryDirectory.appendingPathComponent("removal-backup-" + UUID().uuidString).resolvingSymlinksInPath()
        let source = root.appendingPathComponent("Installed")
        let backups = root.appendingPathComponent("Backups")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        return (root, source, backups)
    }

    private func makeBundle(_ url: URL, payload: String) throws -> URL {
        let contents = url.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.example.fixture"], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(payload.utf8).write(to: contents.appendingPathComponent("Payload"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: contents.appendingPathComponent("Payload").path)
        return url
    }

    private func permissions(of url: URL) -> UInt16? {
        let attributes = try? fm.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.uint16Value
    }
}
