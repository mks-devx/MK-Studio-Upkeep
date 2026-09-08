// SPDX-License-Identifier: BUSL-1.1
import AppKit
import Combine
import Foundation
import ProducerUpToDateCore

struct SoftwareUpdateItem: Identifiable {
    enum Kind: String {
        case plugin = "Plugin"
        case daw = "DAW"
    }

    let id: String
    let kind: Kind
    let name: String
    let vendor: String
    let installedVersion: String
    let latestVersion: String
    let architecture: String

    init(_ result: PluginUpdateResult) {
        id = "plugin:\(result.id)"
        kind = .plugin
        name = result.product.name
        vendor = result.product.vendor ?? "Unknown vendor"
        installedVersion = result.installedVersion ?? "Unknown"
        latestVersion = result.latestVersion ?? "Unknown"
        if result.product.architectures.contains(.arm64)
            && result.product.architectures.contains(.x86_64) {
            architecture = "Apple Silicon + Intel"
        } else if result.product.architectures.isEmpty {
            architecture = "Unknown"
        } else {
            architecture = result.product.architectures
                .map(\.displayName)
                .sorted()
                .joined(separator: " + ")
        }
    }

    init(_ daw: InstalledDAWRecord) {
        id = "daw:\(daw.id)"
        kind = .daw
        name = daw.name
        vendor = daw.vendor
        installedVersion = daw.conciseInstalledVersion ?? "Unknown"
        latestVersion = daw.latestVersion ?? "Unknown"
        architecture = daw.architectureSummary
    }
}

enum InventorySection: String, CaseIterable, Identifiable {
    /// One screen of counts from the last scan; each card opens its section.
    case caches = "Cache inspection"
    case tips = "Tips"
    case overview = "Overview"
    case needsAttention = "Needs Attention"
    case updatesAvailable = "Updates Available"
    /// Compared against the catalogue and current.
    case upToDate = "Matches listed version"
    /// Not compared; a vendor app owns the updates.
    case managedElsewhere = "Managed by vendor app"
    /// Neither compared nor owned by a vendor app: confirm an identity, check the vendor site, or wait for coverage.
    case notChecked = "Update status unknown"
    /// Products whose installed files contain no Apple Silicon code.
    case intelOnly = "Intel-only copies"
    case allPlugins = "Plugins"
    case allDAWs = "DAWs"
    case hardware = "Hardware"
    case drivers = "Drivers"
    case managers = "Software Managers"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .caches: return "internaldrive"
        case .tips: return "lightbulb"
        case .overview:
            return "square.grid.2x2"
        case .needsAttention:
            return "exclamationmark.triangle"
        case .updatesAvailable:
            return "arrow.down.circle"
        case .upToDate:
            return "checkmark.circle"
        case .managedElsewhere:
            return "square.stack.3d.up"
        case .notChecked:
            return "questionmark.circle"
        case .intelOnly:
            return "cpu"
        case .allPlugins:
            return "waveform"
        case .hardware: return "hifispeaker"
        case .drivers: return "puzzlepiece.extension"
        case .managers: return "square.stack.3d.up"
        case .allDAWs:
            return "slider.horizontal.3"
        }
    }
}

extension LocalReviewFilter {
    static var navigationCases: [Self] { allCases.filter { $0 != .all } }
    var navigationTitle: String {
        switch self {
        case .all: "All findings"
        case .cannotRun: "Cannot run on this Mac"
        case .differentVersions: "Different versions"
        case .repeatedCopies: "Multiple copies"
        case .relatedEditions: "Related editions"
        }
    }
    var navigationSymbol: String {
        switch self {
        case .all: "list.bullet"
        case .cannotRun: "nosign"
        case .differentVersions: "arrow.triangle.branch"
        case .repeatedCopies: "doc.on.doc"
        case .relatedEditions: "square.stack"
        }
    }
}
