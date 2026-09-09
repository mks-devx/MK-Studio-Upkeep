// SPDX-License-Identifier: AGPL-3.0-only
import CryptoKit
import Foundation

public struct RemovalBackupPreferences: Sendable {
    public static let enabledKey = "removalBackupsEnabled"
    public static let automaticDeletionKey = "removalBackupsAutomaticDeletion"
    public static let retentionDaysKey = "removalBackupsRetentionDays"

    public let isEnabled: Bool
    public let automaticallyDeletesExpired: Bool
    public let retentionDays: Int

    public init(defaults: UserDefaults = .standard) {
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        automaticallyDeletesExpired = defaults.object(forKey: Self.automaticDeletionKey) as? Bool ?? true
        let stored = defaults.object(forKey: Self.retentionDaysKey) as? Int
        retentionDays = [7, 30, 90].contains(stored ?? 30) ? (stored ?? 30) : 30
    }
}

public enum RemovalBackupItemState: String, Codable, Sendable { case backedUp, removed, restored }

public struct RemovalBackupItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let originalPath: String
    public let kind: CleanupItemKind
    public let payloadRelativePath: String
    public let byteCount: Int64
    public let contentFingerprint: String
    public var movedAt: Date?
    public var restoredAt: Date?

    public var state: RemovalBackupItemState {
        if restoredAt != nil { return .restored }
        if movedAt != nil { return .removed }
        return .backedUp
    }
}

public struct RemovalBackupManifest: Codable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let id: UUID
    public let displayName: String
    public let createdAt: Date
    public let expiresAt: Date
    public var items: [RemovalBackupItem]

    public var byteCount: Int64 { items.reduce(0) { $0 + $1.byteCount } }
    public var removedItemCount: Int { items.filter { $0.movedAt != nil }.count }
    public var restoredItemCount: Int { items.filter { $0.restoredAt != nil }.count }
}

public struct RemovalBackupDeletionSummary: Equatable, Sendable {
    public let operationCount: Int
    public let byteCount: Int64
    public init(operationCount: Int, byteCount: Int64) {
        self.operationCount = operationCount
        self.byteCount = byteCount
    }
}

public enum RemovalBackupError: Error, Equatable, LocalizedError {
    case emptyPlan, planTooLarge, invalidRetention, unsafeSource, copyFailed, verificationFailed
    case invalidManifest, operationMissing, itemMissing, destinationOccupied, destinationUnsafe
    case restoreFailed, restoreVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPlan: "Select at least one software bundle."
        case .planTooLarge: "Too many software bundles were selected for one removal. Nothing was removed."
        case .invalidRetention: "The selected backup retention period is invalid."
        case .unsafeSource: "A selected item no longer passes the removal safety review."
        case .copyFailed: "A complete local backup could not be created. Nothing was removed."
        case .verificationFailed: "The backup copy could not be verified. Nothing was removed."
        case .invalidManifest: "This backup record is damaged or unsafe to use."
        case .operationMissing: "This backup no longer exists."
        case .itemMissing: "The selected item is not part of this backup."
        case .destinationOccupied: "Software already exists at the original location. Nothing was replaced."
        case .destinationUnsafe: "The original location is no longer an approved restore destination."
        case .restoreFailed: "The backup could not be restored. The recovery copy remains available."
        case .restoreVerificationFailed: "The restored item could not be verified. The recovery copy remains available; inspect the original location before opening a DAW."
        }
    }
}

public actor RemovalBackupStore {
    public static let folderName = "Removal Backups"
    public nonisolated let root: URL
    private let now: () -> Date
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        self.now = now
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func prepare(plan: CleanupPlan, safety: CleanupSafety, retentionDays: Int) throws -> RemovalBackupManifest {
        guard !plan.items.isEmpty else { throw RemovalBackupError.emptyPlan }
        guard plan.items.count <= 1_000 else { throw RemovalBackupError.planTooLarge }
        guard (1...3_650).contains(retentionDays) else { throw RemovalBackupError.invalidRetention }
        guard Set(plan.items.map { $0.path.standardizedFileURL.path }).count == plan.items.count else {
            throw RemovalBackupError.unsafeSource
        }
        guard plan.items.allSatisfy({ safety.validate($0) == nil }) else { throw RemovalBackupError.unsafeSource }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let operationID = UUID()
        let staging = root.appendingPathComponent(".staging-" + operationID.uuidString, isDirectory: true)
        let destination = root.appendingPathComponent(operationID.uuidString, isDirectory: true)
        var committed = false
        defer { if !committed { try? fileManager.removeItem(at: staging) } }
        try fileManager.createDirectory(at: staging.appendingPathComponent("Payload", isDirectory: true), withIntermediateDirectories: true)
        var records: [RemovalBackupItem] = []
        do {
            for item in plan.items {
                guard safety.validate(item) == nil else { throw RemovalBackupError.unsafeSource }
                let itemID = UUID()
                let relative = "Payload/" + itemID.uuidString
                let payload = staging.appendingPathComponent(relative, isDirectory: true)
                let sourceFingerprint = try BackupContentFingerprint.scan(item.path)
                try fileManager.copyItem(at: item.path.standardizedFileURL, to: payload)
                let copyFingerprint = try BackupContentFingerprint.scan(payload)
                guard sourceFingerprint.digest == copyFingerprint.digest,
                      sourceFingerprint.byteCount == copyFingerprint.byteCount else { throw RemovalBackupError.verificationFailed }
                records.append(RemovalBackupItem(id: itemID, originalPath: item.path.standardizedFileURL.path,
                    kind: item.kind, payloadRelativePath: relative, byteCount: sourceFingerprint.byteCount,
                    contentFingerprint: sourceFingerprint.digest, movedAt: nil, restoredAt: nil))
            }
        } catch let error as RemovalBackupError { throw error }
        catch { throw RemovalBackupError.copyFailed }
        let created = now()
        let manifest = RemovalBackupManifest(schemaVersion: RemovalBackupManifest.currentSchemaVersion,
            id: operationID, displayName: DisplaySanitiser.sanitise(plan.displayName) ?? "Software removal",
            createdAt: created, expiresAt: created.addingTimeInterval(TimeInterval(retentionDays) * 86_400), items: records)
        try write(manifest, in: staging)
        do { try fileManager.moveItem(at: staging, to: destination) }
        catch { throw RemovalBackupError.copyFailed }
        committed = true
        return manifest
    }

    public func list() throws -> [RemovalBackupManifest] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard urls.count <= 2_000 else { throw RemovalBackupError.invalidManifest }
        return try urls.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return try load(from: directory)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func recordRemoval(operationID: UUID, movedPaths: Set<String>) throws -> RemovalBackupManifest {
        let directory = try operationDirectory(operationID)
        var manifest = try load(from: directory)
        let timestamp = now()
        for index in manifest.items.indices where movedPaths.contains(manifest.items[index].originalPath) {
            manifest.items[index].movedAt = timestamp
        }
        try write(manifest, in: directory)
        return manifest
    }

    public func restore(operationID: UUID, itemID: UUID, safety: CleanupSafety) throws -> URL {
        try restore(operationID: operationID, itemID: itemID, safety: safety, install: Self.directInstall)
    }

    public func restore(operationID: UUID, itemID: UUID, safety: CleanupSafety,
                        install: @Sendable (URL, URL) throws -> Void) throws -> URL {
        let directory = try operationDirectory(operationID)
        var manifest = try load(from: directory)
        guard let index = manifest.items.firstIndex(where: { $0.id == itemID }) else { throw RemovalBackupError.itemMissing }
        let record = manifest.items[index]
        let destination = URL(fileURLWithPath: record.originalPath).standardizedFileURL
        guard !fileManager.fileExists(atPath: destination.path) else { throw RemovalBackupError.destinationOccupied }
        guard safety.validateRestoreDestination(destination, kind: record.kind) == nil else { throw RemovalBackupError.destinationUnsafe }
        let payload = directory.appendingPathComponent(record.payloadRelativePath, isDirectory: true).standardizedFileURL
        guard isContained(payload, in: directory), fileManager.fileExists(atPath: payload.path),
              try BackupContentFingerprint.scan(payload).digest == record.contentFingerprint else { throw RemovalBackupError.invalidManifest }
        let stagingDirectory = directory.appendingPathComponent(".restore-" + UUID().uuidString, isDirectory: true)
        let staged = stagingDirectory.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
            try fileManager.copyItem(at: payload, to: staged)
            guard try BackupContentFingerprint.scan(staged).digest == record.contentFingerprint else { throw RemovalBackupError.restoreVerificationFailed }
            guard !fileManager.fileExists(atPath: destination.path) else { throw RemovalBackupError.destinationOccupied }
            try install(staged, destination)
            guard fileManager.fileExists(atPath: destination.path),
                  try BackupContentFingerprint.scan(destination).digest == record.contentFingerprint else {
                throw RemovalBackupError.restoreVerificationFailed
            }
        } catch let error as RemovalBackupError { throw error }
        catch { throw RemovalBackupError.restoreFailed }
        manifest.items[index].restoredAt = now()
        try write(manifest, in: directory)
        return destination
    }

    private nonisolated static func directInstall(_ source: URL, _ destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func deleteExpired() throws -> RemovalBackupDeletionSummary {
        let summary = try delete(list().filter { $0.expiresAt <= now() })
        try removeAbandonedStaging(olderThan: now().addingTimeInterval(-86_400))
        return summary
    }
    public func deleteAll() throws -> RemovalBackupDeletionSummary {
        let summary = try delete(list())
        try removeAbandonedStaging(olderThan: nil)
        return summary
    }

    private func delete(_ manifests: [RemovalBackupManifest]) throws -> RemovalBackupDeletionSummary {
        var count = 0
        var bytes: Int64 = 0
        for manifest in manifests {
            try fileManager.removeItem(at: try operationDirectory(manifest.id))
            count += 1
            bytes += manifest.byteCount
        }
        return .init(operationCount: count, byteCount: bytes)
    }

    private func removeAbandonedStaging(olderThan cutoff: Date?) throws {
        guard fileManager.fileExists(atPath: root.path) else { return }
        let candidates = try fileManager.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [])
        for candidate in candidates {
            let name = candidate.lastPathComponent
            guard name.hasPrefix(".staging-"), UUID(uuidString: String(name.dropFirst(".staging-".count))) != nil,
                  isRealDirectory(candidate) else { continue }
            if let cutoff {
                guard let modified = try? candidate.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified <= cutoff else { continue }
            }
            try fileManager.removeItem(at: candidate)
        }
    }

    private func operationDirectory(_ id: UUID) throws -> URL {
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true).standardizedFileURL
        guard isContained(directory, in: root), fileManager.fileExists(atPath: directory.path) else { throw RemovalBackupError.operationMissing }
        return directory
    }

    private func load(from directory: URL) throws -> RemovalBackupManifest {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard isRealDirectory(directory), isContained(manifestURL, in: directory), let data = SafeFileAccess.data(at: manifestURL, maximumBytes: 2_097_152),
              JSONDepth.isWithinLimit(data), var manifest = try? decoder.decode(RemovalBackupManifest.self, from: data),
              manifest.schemaVersion == RemovalBackupManifest.currentSchemaVersion,
              manifest.id.uuidString == directory.lastPathComponent, !manifest.items.isEmpty,
              Set(manifest.items.map(\.id)).count == manifest.items.count else { throw RemovalBackupError.invalidManifest }
        manifest.items = try manifest.items.map { item in
            let payload = directory.appendingPathComponent(item.payloadRelativePath)
            guard item.originalPath.hasPrefix("/"), item.payloadRelativePath == "Payload/" + item.id.uuidString,
                  item.byteCount >= 0, isContained(payload, in: directory), isRealDirectory(payload) else {
                throw RemovalBackupError.invalidManifest
            }
            return item
        }
        return manifest
    }

    private func write(_ manifest: RemovalBackupManifest, in directory: URL) throws {
        let data = try encoder.encode(manifest)
        guard data.count <= 2_097_152 else { throw RemovalBackupError.invalidManifest }
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func isContained(_ url: URL, in base: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path + "/")
    }

    private func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}

private enum BackupContentFingerprint {
    struct Result { let digest: String; let byteCount: Int64 }

    static func scan(_ root: URL, maximumEntries: Int = 250_000) throws -> Result {
        let root = root.standardizedFileURL
        guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw RemovalBackupError.verificationFailed
        }
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, _ in
            enumerationFailed = true
            return false
        }) else {
            throw RemovalBackupError.copyFailed
        }
        var entries: [(String, String)] = []
        var total: Int64 = 0
        let prefix = root.path + "/"
        for case let url as URL in enumerator {
            guard entries.count < maximumEntries else { throw RemovalBackupError.copyFailed }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw RemovalBackupError.verificationFailed }
            let relative = String(path.dropFirst(prefix.count))
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let type = attributes[.type] as? FileAttributeType
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            if type == .typeSymbolicLink {
                enumerator.skipDescendants()
                entries.append((relative, "link:\(permissions):" + (try FileManager.default.destinationOfSymbolicLink(atPath: path))))
            } else if type == .typeRegular {
                total += (attributes[.size] as? NSNumber)?.int64Value ?? 0
                entries.append((relative, "file:\(permissions):" + (try hashFile(url))))
            } else if type == .typeDirectory { entries.append((relative, "directory:\(permissions)")) }
            else { throw RemovalBackupError.verificationFailed }
        }
        guard !enumerationFailed else { throw RemovalBackupError.copyFailed }
        var hasher = SHA256()
        for entry in entries.sorted(by: { $0.0 < $1.0 }) {
            hasher.update(data: Data(entry.0.utf8)); hasher.update(data: Data([0]))
            hasher.update(data: Data(entry.1.utf8)); hasher.update(data: Data([0]))
        }
        return Result(digest: hasher.finalize().map { String(format: "%02x", $0) }.joined(), byteCount: total)
    }

    private static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct BackupProtectedCleanupResult: Sendable {
    public let cleanup: CleanupExecutionResult
    public let backup: RemovalBackupManifest?
}

public enum BackupProtectedCleanupExecutor {
    public static func execute(plan: CleanupPlan, safety: CleanupSafety,
                               store: RemovalBackupStore, retentionDays: Int,
                               moveToTrash: (URL) throws -> Void) async -> BackupProtectedCleanupResult {
        let prepared: RemovalBackupManifest
        do {
            prepared = try await store.prepare(plan: plan, safety: safety, retentionDays: retentionDays)
        } catch {
            return BackupProtectedCleanupResult(
                cleanup: CleanupExecutionResult(movedCount: 0,
                    failures: [error.localizedDescription]),
                backup: nil)
        }
        var movedPaths = Set<String>()
        let cleanup = CleanupExecutor.execute(plan, safety: safety) { url in
            try moveToTrash(url)
            movedPaths.insert(url.standardizedFileURL.path)
        }
        do {
            let updated = try await store.recordRemoval(operationID: prepared.id, movedPaths: movedPaths)
            return BackupProtectedCleanupResult(cleanup: cleanup, backup: updated)
        } catch {
            let failures = cleanup.failures + ["The backup is intact, but its removal status could not be updated: \(error.localizedDescription)"]
            return BackupProtectedCleanupResult(
                cleanup: CleanupExecutionResult(movedCount: cleanup.movedCount, failures: failures),
                backup: prepared)
        }
    }
}
