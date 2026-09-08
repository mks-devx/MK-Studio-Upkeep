// SPDX-License-Identifier: BUSL-1.1
import Foundation
import ProducerUpToDateCore
import UpdateEnginePrototypeSupport

public enum OfficialProductKind: String, Codable, Sendable { case plugin, daw }
public enum OfficialAdapter: String, Codable, Sendable { case fabfilterCurrent, fabfilterLegacy, reaper }
public struct OfficialSource: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: OfficialProductKind
    public let identifiers: [String]
    public let names: [String]
    public let major: Int
    public let source: URL
    public let adapter: OfficialAdapter
    public let reviewedOn: String
    public let provenance: URL
    public let successor: String?
}
public enum OfficialCheckError: String, Error, LocalizedError {
    case directory = "The official source directory could not be loaded."
    case ambiguous = "The source changed or its release information is ambiguous."
    case network = "The official source could not be reached safely."
    case permission = "Online checks are off."
    public var errorDescription: String? { rawValue }
}

/// Data-only source and identity mappings; never contains current release versions.
/// Only a packaged, reviewed seed is trusted in this first integration. Remote directory
/// delivery requires a signed envelope and rollback protection before it can be enabled.
public struct OfficialSourceDirectory: Codable, Sendable {
    public let schema: Int
    public let entries: [OfficialSource]
    public static func bundled() throws -> Self {
        // Packaged apps keep resources inside Contents/Resources. SwiftPM supplies its
        // own bundle when tests or diagnostic executables are run from the build tree.
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("official-sources.json")
        let url: URL?
        if Bundle.main.bundleURL.pathExtension == "app" {
            url = packaged
        } else {
            url = Bundle.module.url(forResource: "official-sources", withExtension: "json")
        }
        guard let url, let data = SafeFileAccess.data(at: url, maximumBytes: 131_072) else { throw OfficialCheckError.directory }
        return try decode(data)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 131_072, JSONDepth.isWithinLimit(data) else { throw OfficialCheckError.directory }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schema == 1, (1...32).contains(value.entries.count), Set(value.entries.map(\.id)).count == value.entries.count else { throw OfficialCheckError.directory }
        for entry in value.entries {
            let expected: String
            switch entry.adapter {
            case .fabfilterCurrent: expected = "https://www.fabfilter.com/download"
            case .fabfilterLegacy: expected = "https://www.fabfilter.com/support/downloads"
            case .reaper: expected = "https://www.reaper.fm/download.php"
            }
            guard entry.source.absoluteString == expected, PublicFeedTransport.acceptedURL(entry.source),
                  PublicFeedTransport.acceptedURL(entry.provenance), entry.major > 0,
                  !entry.identifiers.isEmpty, !entry.names.isEmpty,
                  ([entry.id, entry.name] + entry.identifiers + entry.names).allSatisfy({ DisplaySanitiser.sanitise($0) == $0 }),
                  EvidenceFreshness.date(entry.reviewedOn) != nil,
                  entry.successor == nil || value.entries.contains(where: { $0.id == entry.successor && $0.id != entry.id })
            else { throw OfficialCheckError.directory }
        }
        return value
    }
    public func match(identifier: String?, name: String, version: String?, kind: OfficialProductKind) -> OfficialSource? {
        guard let identifier, let version, let parsed = VersionComparator.parse(version), parsed.channel == .stable else { return nil }
        let matches = entries.filter {
            $0.kind == kind && $0.identifiers.contains(identifier) && $0.names.contains(name) && $0.major == parsed.numbers.first
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
