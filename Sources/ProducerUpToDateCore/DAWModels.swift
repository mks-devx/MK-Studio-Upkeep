// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum UpdateCheckState: String, Codable, Sendable {
    case notChecked = "Not checked"
    case current = "Up to date"
    case updateAvailable = "Update available"
    case unavailable = "Could not verify"
}

public struct DAWDefinition: Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let vendor: String
    public let bundleIdentifiers: Set<String>
    public let applicationNamePrefixes: [String]

    public init(
        id: String,
        name: String,
        vendor: String,
        bundleIdentifiers: Set<String>,
        applicationNamePrefixes: [String]
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.bundleIdentifiers = bundleIdentifiers
        self.applicationNamePrefixes = applicationNamePrefixes
    }
}

public struct InstalledDAWRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let definitionID: String
    public let name: String
    public let vendor: String
    public let bundleIdentifier: String?
    public let displayVersion: String?
    public let buildVersion: String?
    public let path: URL
    public let executablePath: URL?
    public let architectures: [BinaryArchitecture]
    public let identityIsInferred: Bool
    /// A Mac App Store receipt file exists inside the bundle. This is an installation
    /// hint for routing updates to the App Store, not a validated purchase.
    public let installedFromAppStore: Bool
    public let updateState: UpdateCheckState
    public let latestVersion: String?
    public let updateSourceURL: URL?
    public var checkMethod: ReleaseCheckMethod? = nil
    public let updateCheckedOn: String?

    public init(
        id: String,
        definitionID: String,
        name: String,
        vendor: String,
        bundleIdentifier: String?,
        displayVersion: String?,
        buildVersion: String?,
        path: URL,
        executablePath: URL?,
        architectures: [BinaryArchitecture],
        identityIsInferred: Bool = false,
        installedFromAppStore: Bool = false,
        updateState: UpdateCheckState = .notChecked,
        latestVersion: String? = nil,
        updateSourceURL: URL? = nil,
        updateCheckedOn: String? = nil
    ) {
        self.id = id
        self.definitionID = definitionID
        self.name = name
        self.vendor = vendor
        self.bundleIdentifier = bundleIdentifier
        self.displayVersion = displayVersion
        self.buildVersion = buildVersion
        self.path = path
        self.executablePath = executablePath
        self.architectures = architectures
        self.identityIsInferred = identityIsInferred
        self.installedFromAppStore = installedFromAppStore
        self.updateState = updateState
        self.latestVersion = latestVersion
        self.updateSourceURL = updateSourceURL
        self.updateCheckedOn = updateCheckedOn
    }

    public func withoutUpdateEvidence() -> InstalledDAWRecord {
        InstalledDAWRecord(id: id, definitionID: definitionID, name: name, vendor: vendor,
            bundleIdentifier: bundleIdentifier, displayVersion: displayVersion, buildVersion: buildVersion,
            path: path, executablePath: executablePath, architectures: architectures, identityIsInferred: identityIsInferred,
            installedFromAppStore: installedFromAppStore)
    }

    public var installedVersion: String? {
        displayVersion ?? buildVersion
    }

    public var conciseInstalledVersion: String? {
        guard let installedVersion else {
            return nil
        }
        let pattern = #"^[vV]?([0-9]+(?:\.[0-9]+)*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return installedVersion
        }
        let range = NSRange(
            installedVersion.startIndex..<installedVersion.endIndex,
            in: installedVersion
        )
        guard let match = expression.firstMatch(
            in: installedVersion,
            range: range
        ),
        let captureRange = Range(match.range(at: 1), in: installedVersion)
        else {
            return installedVersion
        }
        return String(installedVersion[captureRange])
    }

    public var architectureSummary: String {
        if architectures.contains(.arm64) && architectures.contains(.x86_64) {
            return "Apple Silicon + Intel"
        }
        if architectures.isEmpty {
            return "Unknown"
        }
        return architectures.map(\.displayName).joined(separator: " + ")
    }
}

public struct DAWReleaseRecord: Hashable, Codable, Sendable {
    public let definitionID: String
    public let latestVersion: String
    public let sourceURL: URL
    public let checkedOn: String
    public var checkMethod: ReleaseCheckMethod? = nil
    public let majorVersion: Int?

    public init(
        definitionID: String,
        latestVersion: String,
        sourceURL: URL,
        checkedOn: String,
        majorVersion: Int? = nil
    ) {
        self.definitionID = definitionID
        self.latestVersion = latestVersion
        self.sourceURL = sourceURL
        self.checkedOn = checkedOn
        self.majorVersion = majorVersion
    }
}

public enum ReviewedDAWCatalogue {
    /// Compatibility accessor. Release comparisons require explicit input; no catalogue ships.
    public static var bundled: [DAWReleaseRecord] { [] }
}

public struct DAWScanConfiguration: Hashable, Codable, Sendable {
    public let applicationRoots: [URL]
    public let definitions: [DAWDefinition]

    public init(
        applicationRoots: [URL],
        definitions: [DAWDefinition]
    ) {
        self.applicationRoots = applicationRoots
        self.definitions = definitions
    }

    public static var standard: DAWScanConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return DAWScanConfiguration(
            applicationRoots: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true)
            ],
            definitions: DAWDefinition.known
        )
    }
}

public extension DAWDefinition {
    static let known: [DAWDefinition] = [
        DAWDefinition(id: "ableton-live", name: "Ableton Live", vendor: "Ableton", bundleIdentifiers: ["com.ableton.live"], applicationNamePrefixes: ["Ableton Live"]),
        DAWDefinition(id: "logic-pro", name: "Logic Pro", vendor: "Apple", bundleIdentifiers: ["com.apple.logic10", "com.apple.mobilelogic"], applicationNamePrefixes: ["Logic Pro"]),
        DAWDefinition(id: "garageband", name: "GarageBand", vendor: "Apple", bundleIdentifiers: ["com.apple.garageband10"], applicationNamePrefixes: ["GarageBand"]),
        DAWDefinition(id: "fl-studio", name: "FL Studio", vendor: "Image-Line", bundleIdentifiers: ["com.image-line.flstudio"], applicationNamePrefixes: ["FL Studio"]),
        DAWDefinition(id: "cubase", name: "Cubase", vendor: "Steinberg", bundleIdentifiers: [], applicationNamePrefixes: ["Cubase"]),
        DAWDefinition(id: "nuendo", name: "Nuendo", vendor: "Steinberg", bundleIdentifiers: [], applicationNamePrefixes: ["Nuendo"]),
        DAWDefinition(id: "pro-tools", name: "Pro Tools", vendor: "Avid", bundleIdentifiers: ["com.avid.ProTools"], applicationNamePrefixes: ["Pro Tools"]),
        DAWDefinition(id: "studio-one", name: "Studio One", vendor: "PreSonus", bundleIdentifiers: [], applicationNamePrefixes: ["Studio One"]),
        DAWDefinition(id: "reaper", name: "REAPER", vendor: "Cockos", bundleIdentifiers: ["com.cockos.reaper"], applicationNamePrefixes: ["REAPER"]),
        DAWDefinition(id: "bitwig-studio", name: "Bitwig Studio", vendor: "Bitwig", bundleIdentifiers: ["com.bitwig.BitwigStudio"], applicationNamePrefixes: ["Bitwig Studio"]),
        DAWDefinition(id: "reason", name: "Reason", vendor: "Reason Studios", bundleIdentifiers: ["se.propellerheads.reason"], applicationNamePrefixes: ["Reason"]),
        DAWDefinition(id: "digital-performer", name: "Digital Performer", vendor: "MOTU", bundleIdentifiers: [], applicationNamePrefixes: ["Digital Performer"]),
        DAWDefinition(id: "maschine", name: "Maschine", vendor: "Native Instruments", bundleIdentifiers: ["com.native-instruments.Maschine 3"], applicationNamePrefixes: ["Maschine"]),
        DAWDefinition(id: "waveform", name: "Waveform", vendor: "Tracktion", bundleIdentifiers: [], applicationNamePrefixes: ["Waveform"]),
        DAWDefinition(id: "luna", name: "LUNA", vendor: "Universal Audio", bundleIdentifiers: [], applicationNamePrefixes: ["LUNA"]),
        DAWDefinition(id: "ardour", name: "Ardour", vendor: "Ardour", bundleIdentifiers: ["org.ardour.Ardour"], applicationNamePrefixes: ["Ardour"]),
        DAWDefinition(id: "renoise", name: "Renoise", vendor: "Renoise", bundleIdentifiers: [], applicationNamePrefixes: ["Renoise"]),
        DAWDefinition(id: "mixbus", name: "Mixbus", vendor: "Harrison", bundleIdentifiers: [], applicationNamePrefixes: ["Mixbus"]),
        DAWDefinition(id: "mulab", name: "MuLab", vendor: "MuTools", bundleIdentifiers: [], applicationNamePrefixes: ["MuLab"]),
        DAWDefinition(id: "n-track", name: "n-Track Studio", vendor: "n-Track", bundleIdentifiers: [], applicationNamePrefixes: ["n-Track"]),
        DAWDefinition(id: "lmms", name: "LMMS", vendor: "LMMS", bundleIdentifiers: [], applicationNamePrefixes: ["LMMS"]),
        DAWDefinition(id: "zrythm", name: "Zrythm", vendor: "Zrythm", bundleIdentifiers: [], applicationNamePrefixes: ["Zrythm"]),
        DAWDefinition(id: "mpc", name: "MPC", vendor: "Akai Professional", bundleIdentifiers: [], applicationNamePrefixes: ["MPC"]),
        DAWDefinition(id: "fender-studio-pro", name: "Fender Studio Pro", vendor: "Fender", bundleIdentifiers: [], applicationNamePrefixes: ["Fender Studio Pro"])

    ]
}
