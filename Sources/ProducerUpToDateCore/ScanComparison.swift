// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// A compact record of one scan, kept on this Mac so the next scan can say what changed.
/// Names and versions only: no paths, no evidence, nothing about the machine.
public struct ScanSnapshot: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let vendor: String
        public let version: String
    }
    public static let maximumEntries = 20_000
    public static let maximumBytes = 4_194_304
    private static let currentIdentitySchemaVersion = 2
    /// Nil in snapshots saved before product identity stopped depending on format count.
    public let identitySchemaVersion: Int?
    public let scopeID: String?
    public let finishedAt: Date
    public let entries: [Entry]

    public init(finishedAt: Date, products: [NormalizedPluginProduct], scopeID: String? = nil) {
        self.identitySchemaVersion = Self.currentIdentitySchemaVersion
        self.scopeID = scopeID
        self.finishedAt = finishedAt
        entries = products.prefix(Self.maximumEntries).map { product in
            Entry(id: product.id, name: product.name, vendor: product.vendor ?? "",
                  version: Array(Set(product.bundles.compactMap(\.displayVersion))).sorted().joined(separator: " / "))
        }
    }

    public static func load(from url: URL) -> ScanSnapshot? {
        guard let data = SafeFileAccess.data(at: url, maximumBytes: maximumBytes), JSONDepth.isWithinLimit(data),
              let value = try? JSONDecoder().decode(ScanSnapshot.self, from: data),
              value.entries.count <= maximumEntries,
              Set(value.entries.map(\.id)).count == value.entries.count,
              value.entries.allSatisfy({ entry in
                  [entry.name, entry.vendor, entry.version].allSatisfy {
                      $0.isEmpty || DisplaySanitiser.sanitise($0, maximumLength: 256) == $0
                  }
              }),
              value.entries.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 256 && $0.name.count <= 256 && $0.vendor.count <= 256 && $0.version.count <= 128 }) else { return nil }
        return value
    }

    public func canCompare(to other: ScanSnapshot) -> Bool {
        guard identitySchemaVersion == Self.currentIdentitySchemaVersion,
              other.identitySchemaVersion == Self.currentIdentitySchemaVersion,
              let scopeID, entries.count < Self.maximumEntries, other.entries.count < Self.maximumEntries else { return false }
        return scopeID == other.scopeID
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// What changed between two scans of the same Mac.
public struct ScanComparison: Equatable, Sendable {
    public struct Change: Equatable, Sendable, Identifiable {
        public var id: String { entry.id }
        public let entry: ScanSnapshot.Entry
        public let previousVersion: String?
    }
    public let previousFinishedAt: Date
    public let added: [Change]
    public let removed: [Change]
    public let changed: [Change]
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    public init(previous: ScanSnapshot, current: ScanSnapshot) {
        previousFinishedAt = previous.finishedAt
        let before = Dictionary(previous.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(current.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func sorted(_ changes: [Change]) -> [Change] { changes.sorted { $0.entry.name.localizedStandardCompare($1.entry.name) == .orderedAscending } }
        added = sorted(after.values.filter { before[$0.id] == nil }.map { Change(entry: $0, previousVersion: nil) })
        removed = sorted(before.values.filter { after[$0.id] == nil }.map { Change(entry: $0, previousVersion: nil) })
        changed = sorted(after.values.compactMap { entry in
            guard let old = before[entry.id], old.version != entry.version else { return nil }
            return Change(entry: entry, previousVersion: old.version)
        })
    }
}
