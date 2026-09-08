// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum PluginFormat: String, CaseIterable, Codable, Sendable {
    case audioUnit = "Audio Unit"
    case vst3 = "VST3"
    case vst2 = "VST2"
    case clap = "CLAP"

    public var pathExtension: String {
        switch self {
        case .audioUnit:
            return "component"
        case .vst3:
            return "vst3"
        case .vst2:
            return "vst"
        case .clap:
            return "clap"
        }
    }

    public var defaultFolderName: String {
        switch self {
        case .audioUnit:
            return "Components"
        case .vst3:
            return "VST3"
        case .vst2:
            return "VST"
        case .clap:
            return "CLAP"
        }
    }
}

public enum BinaryArchitecture: String, CaseIterable, Codable, Sendable {
    case arm64
    case x86_64
    case arm
    case i386
    case unknown

    public var displayName: String {
        switch self {
        case .arm64:
            return "Apple Silicon"
        case .x86_64:
            return "Intel 64-bit"
        case .arm:
            return "ARM"
        case .i386:
            return "Intel 32-bit"
        case .unknown:
            return "Unknown"
        }
    }
}

public enum EvidenceKind: String, Codable, Sendable {
    case bundleInformation = "Bundle information"
    case audioComponent = "Audio Component bundle metadata"
    case vst3ModuleInfo = "VST3 module information"
    case executable = "Plugin executable"
    case inferred = "Inferred"
}

public struct VersionEvidence: Hashable, Codable, Sendable {
    public let kind: EvidenceKind
    public let field: String
    public let value: String

    public init(kind: EvidenceKind, field: String, value: String) {
        self.kind = kind
        self.field = field
        self.value = value
    }
}

public enum PluginIdentifierKind: String, Codable, Sendable {
    case bundleIdentifier = "Bundle identifier"
    case audioUnitComponent = "Audio Unit component"
    case vst3Class = "VST3 class"
    case clapPlugin = "CLAP plugin"
    case signingTeam = "Code-signing team"
}

public struct PluginIdentifier: Hashable, Codable, Sendable {
    public let kind: PluginIdentifierKind
    public let value: String

    public init(kind: PluginIdentifierKind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public enum ScanIssueSeverity: Int, Comparable, Codable, Sendable {
    case information = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: ScanIssueSeverity, rhs: ScanIssueSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ScanIssue: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let severity: ScanIssueSeverity
    public let title: String
    public let detail: String

    public init(
        id: String,
        severity: ScanIssueSeverity,
        title: String,
        detail: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

public struct PluginBundleRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let vendor: String?
    public let format: PluginFormat
    public let bundleIdentifier: String?
    public let displayVersion: String?
    public let buildVersion: String?
    public let path: URL
    public let executablePath: URL?
    public let architectures: [BinaryArchitecture]
    public let fileSize: Int64?
    public let modifiedAt: Date?
    public let identifiers: [PluginIdentifier]
    public let evidence: [VersionEvidence]
    public let issues: [ScanIssue]
    public let declaredLinks: [DeclaredProductLink]?

    public init(
        id: String,
        name: String,
        vendor: String?,
        format: PluginFormat,
        bundleIdentifier: String?,
        displayVersion: String?,
        buildVersion: String?,
        path: URL,
        executablePath: URL?,
        architectures: [BinaryArchitecture],
        fileSize: Int64?,
        modifiedAt: Date?,
        identifiers: [PluginIdentifier] = [],
        evidence: [VersionEvidence],
        issues: [ScanIssue],
        declaredLinks: [DeclaredProductLink]? = nil
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.format = format
        self.bundleIdentifier = bundleIdentifier
        self.displayVersion = displayVersion
        self.buildVersion = buildVersion
        self.path = path
        self.executablePath = executablePath
        self.architectures = architectures
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.identifiers = identifiers
        self.evidence = evidence
        self.issues = issues
        self.declaredLinks = declaredLinks
    }

    public var architectureSummary: String {
        if architectures.isEmpty {
            return "Unknown"
        }

        return architectures
            .map(\.displayName)
            .joined(separator: " + ")
    }

    public var highestIssueSeverity: ScanIssueSeverity? {
        issues.map(\.severity).max()
    }
}

public struct ScanLocation: Hashable, Codable, Sendable {
    public let url: URL
    public let format: PluginFormat

    public init(url: URL, format: PluginFormat) {
        self.url = url
        self.format = format
    }
}

public struct ScanConfiguration: Hashable, Codable, Sendable {
    public let locations: [ScanLocation]

    public init(locations: [ScanLocation]) {
        self.locations = locations
    }

    public static func includingCustomFolders(_ folders: [URL], enabledFormats: Set<PluginFormat>) -> Self {
        var seen = Set<ScanLocation>()
        let extra = folders.filter(\.isFileURL).flatMap { folder in
            PluginFormat.allCases.map { ScanLocation(url: folder.standardizedFileURL, format: $0) }
        }
        return Self(locations: (standard.locations + extra).filter {
            enabledFormats.contains($0.format) && seen.insert($0).inserted
        })
    }

    public static var standard: ScanConfiguration {
        var locations: [ScanLocation] = []
        let systemRoot = URL(fileURLWithPath: "/Library/Audio/Plug-Ins", isDirectory: true)
        let userRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Audio/Plug-Ins", isDirectory: true)

        for format in PluginFormat.allCases {
            locations.append(
                ScanLocation(
                    url: systemRoot.appendingPathComponent(
                        format.defaultFolderName,
                        isDirectory: true
                    ),
                    format: format
                )
            )
            locations.append(
                ScanLocation(
                    url: userRoot.appendingPathComponent(
                        format.defaultFolderName,
                        isDirectory: true
                    ),
                    format: format
                )
            )
        }

        return ScanConfiguration(locations: locations)
    }
}

public struct ScanLocationResult: Hashable, Codable, Sendable {
    public let location: ScanLocation
    public let wasAccessible: Bool
    public let discoveredCount: Int
    public let errorDescription: String?

    public init(
        location: ScanLocation,
        wasAccessible: Bool,
        discoveredCount: Int,
        errorDescription: String?
    ) {
        self.location = location
        self.wasAccessible = wasAccessible
        self.discoveredCount = discoveredCount
        self.errorDescription = errorDescription
    }
}

public struct ScanReport: Hashable, Codable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let records: [PluginBundleRecord]
    public let locations: [ScanLocationResult]

    public init(
        startedAt: Date,
        finishedAt: Date,
        records: [PluginBundleRecord],
        locations: [ScanLocationResult]
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.records = records
        self.locations = locations
    }

    public var inaccessibleLocationCount: Int {
        locations.filter { !$0.wasAccessible }.count
    }
}

extension PluginBundleRecord {
    /// Preserve each installation path even when format and bundle identities match.
    public static func distinctInstalledCopies(_ records: [PluginBundleRecord]) -> [PluginBundleRecord] {
        var paths = Set<String>()
        return records.sorted { $0.path.path < $1.path.path }.filter {
            paths.insert($0.path.standardizedFileURL.path).inserted
        }
    }
}
