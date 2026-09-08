// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum CatalogueConfidence: Int, Codable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (
        lhs: CatalogueConfidence,
        rhs: CatalogueConfidence
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct CatalogueRelease: Hashable, Codable, Sendable {
    public let productID: String
    public let displayVersion: String
    public let formats: Set<PluginFormat>
    public let architectures: Set<BinaryArchitecture>
    public let officialURL: URL
    public let confidence: CatalogueConfidence
    public let verifiedAt: Date
    public let isFresh: Bool

    public init(
        productID: String,
        displayVersion: String,
        formats: Set<PluginFormat>,
        architectures: Set<BinaryArchitecture>,
        officialURL: URL,
        confidence: CatalogueConfidence,
        verifiedAt: Date,
        isFresh: Bool
    ) {
        self.productID = productID
        self.displayVersion = displayVersion
        self.formats = formats
        self.architectures = architectures
        self.officialURL = officialURL
        self.confidence = confidence
        self.verifiedAt = verifiedAt
        self.isFresh = isFresh
    }
}

public enum NativeMigrationAction: String, Codable, Sendable {
    case update
    case reinstall
    case reviewVersions
}

public enum ArchitectureUpgradeResult: Equatable, Sendable {
    case notApplicable
    case nativeReleaseAvailable(
        version: String,
        action: NativeMigrationAction,
        officialURL: URL
    )
    case nativeReleaseNotConfirmed
    case needsVerification(reason: String)
}

public enum ArchitectureUpgradeEvaluator {
    public static func evaluate(
        installed: PluginBundleRecord,
        release: CatalogueRelease?
    ) -> ArchitectureUpgradeResult {
        guard InstalledArchitecture.classify(installed.architectures) == .intel64 else {
            return .notApplicable
        }

        guard let release else {
            return .nativeReleaseNotConfirmed
        }

        guard release.confidence >= .medium else {
            return .needsVerification(
                reason: "The Apple Silicon release evidence is not strong enough."
            )
        }

        guard release.isFresh else {
            return .needsVerification(
                reason: "The Apple Silicon release evidence needs refreshing."
            )
        }

        guard release.formats.contains(installed.format) else {
            return .nativeReleaseNotConfirmed
        }

        guard release.architectures.contains(.arm64) else {
            return .nativeReleaseNotConfirmed
        }

        guard
            let installedVersion = installed.displayVersion
        else {
            return .nativeReleaseAvailable(
                version: release.displayVersion,
                action: .reviewVersions,
                officialURL: release.officialURL
            )
        }

        switch VersionComparator.compare(
            installedVersion,
            release.displayVersion
        ) {
        case .older:
            return .nativeReleaseAvailable(
                version: release.displayVersion,
                action: .update,
                officialURL: release.officialURL
            )
        case .equal:
            return .nativeReleaseAvailable(
                version: release.displayVersion,
                action: .reinstall,
                officialURL: release.officialURL
            )
        case .newer, .incomparable:
            return .nativeReleaseAvailable(
                version: release.displayVersion,
                action: .reviewVersions,
                officialURL: release.officialURL
            )
        }
    }
}
