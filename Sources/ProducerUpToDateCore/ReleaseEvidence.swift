// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum EvidenceFreshness {
    public static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard value.count == 10, let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    public static func day(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: value)
    }
    public static func isFresh(_ value: String, now: Date = Date(), maximumAgeDays: Int = 30) -> Bool {
        guard let date = date(value) else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < Double(maximumAgeDays) * 86_400
    }
}

public enum ReleaseImportance: String, Codable, Sendable {
    case routine, critical
}

public struct ReviewedReleaseNotes: Hashable, Codable, Sendable, Identifiable {
    public let productID: String
    public let version: String
    public let releaseDate: String?
    public let checkedOn: String
    public let highlights: [String]
    public let sourceURL: URL
    public let importance: ReleaseImportance
    public let criticalReason: String?
    public var id: String { productID + ":" + version }

    public init(productID: String, version: String, releaseDate: String? = nil,
                checkedOn: String, highlights: [String] = [], sourceURL: URL,
                importance: ReleaseImportance = .routine, criticalReason: String? = nil) {
        self.productID = productID; self.version = version; self.releaseDate = releaseDate
        self.checkedOn = checkedOn; self.highlights = highlights; self.sourceURL = sourceURL
        self.importance = importance; self.criticalReason = criticalReason
    }
}

public enum ReleaseNotesQuery {
    public static func releases(productID: String, installed: String, available: String,
                                notes: [ReviewedReleaseNotes], now: Date = Date()) -> [ReviewedReleaseNotes] {
        guard let installed = VersionComparator.releaseValue(installed),
              VersionComparator.compare(installed, available) == .older else { return [] }
        let candidates = notes.filter {
            $0.productID == productID && EvidenceFreshness.isFresh($0.checkedOn, now: now)
                && VersionComparator.compare(installed, $0.version) == .older
                && [.older, .equal].contains(VersionComparator.compare($0.version, available))
        }
        // Ambiguous duplicate evidence is suppressed, never chosen arbitrarily.
        let groups = Dictionary(grouping: candidates, by: \.version)
        return groups.values.compactMap { $0.count == 1 ? $0.first : nil }.sorted {
            VersionComparator.compare($0.version, $1.version) == .newer
        }
    }
}
