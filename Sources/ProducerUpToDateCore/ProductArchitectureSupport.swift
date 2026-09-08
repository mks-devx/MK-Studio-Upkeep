// SPDX-License-Identifier: BUSL-1.1
import Foundation

public struct ArchitectureSupportRecord: Hashable, Codable, Sendable {
    public let vendorIdentifierPrefixes: [String]
    public let exactProductAliases: [String]
    public let productNamePrefixes: [String]
    public let minimumNativeVersion: String
    public let recommendedVersion: String
    public let nativeFormats: Set<PluginFormat>
    public let sourceURL: URL
    public let checkedOn: String

    public init(
        vendorIdentifierPrefixes: [String],
        exactProductAliases: [String] = [],
        productNamePrefixes: [String] = [],
        minimumNativeVersion: String,
        recommendedVersion: String,
        nativeFormats: Set<PluginFormat>,
        sourceURL: URL,
        checkedOn: String
    ) {
        self.vendorIdentifierPrefixes = vendorIdentifierPrefixes
        self.exactProductAliases = exactProductAliases
        self.productNamePrefixes = productNamePrefixes
        self.minimumNativeVersion = minimumNativeVersion
        self.recommendedVersion = recommendedVersion
        self.nativeFormats = nativeFormats
        self.sourceURL = sourceURL
        self.checkedOn = checkedOn
    }
}

public struct ProductArchitectureUpgrade: Equatable, Sendable {
    public let version: String
    public let action: NativeMigrationAction
    public let formats: Set<PluginFormat>
    public let sourceURL: URL
    public let checkedOn: String

    public init(
        version: String,
        action: NativeMigrationAction,
        formats: Set<PluginFormat>,
        sourceURL: URL,
        checkedOn: String
    ) {
        self.version = version
        self.action = action
        self.formats = formats
        self.sourceURL = sourceURL
        self.checkedOn = checkedOn
    }
}

public enum ProductArchitectureCheckResult: Equatable, Sendable {
    case notApplicable
    case nativeReleaseAvailable(ProductArchitectureUpgrade)
    case nativeReleaseNotConfirmed
    case evidenceOutdated(sourceURL: URL, checkedOn: String)
    case needsVerification(reason: String)
}

public enum ProductArchitectureSupportEvaluator {
    public static func evaluate(
        product: NormalizedPluginProduct,
        catalogue: [ArchitectureSupportRecord],
        now: Date = Date()
    ) -> ProductArchitectureCheckResult {
        let intelOnlyBundles = PluginGuidance.intelOnlyBundles(product)
        guard !intelOnlyBundles.isEmpty else {
            return .notApplicable
        }
        guard !product.requiresVerification else {
            return .needsVerification(
                reason: "The product identity must be verified before checking processor support."
            )
        }
        guard let release = catalogue.first(where: {
            matches(product, release: $0)
        }) else {
            return .nativeReleaseNotConfirmed
        }

        guard EvidenceFreshness.isFresh(release.checkedOn, now: now) else {
            return .evidenceOutdated(sourceURL: release.sourceURL, checkedOn: release.checkedOn)
        }
        let installedIntelFormats = Set(intelOnlyBundles.map(\.format))
        let availableFormats = installedIntelFormats
            .intersection(release.nativeFormats)
        guard !availableFormats.isEmpty else {
            return .nativeReleaseNotConfirmed
        }

        guard intelOnlyBundles.filter({ availableFormats.contains($0.format) }).allSatisfy({
            $0.displayVersion.flatMap(VersionComparator.releaseValue) != nil
        }) else {
            return .needsVerification(reason: "Every relevant format needs a comparable release version.")
        }
        let versions = Set(
            intelOnlyBundles
                .filter { availableFormats.contains($0.format) }
                .compactMap { $0.displayVersion ?? $0.buildVersion }
                .compactMap(VersionComparator.releaseValue)
        )
        guard versions.count == 1, let installedVersion = versions.first else {
            return .needsVerification(
                reason: "The Intel-only formats do not share one comparable installed version."
            )
        }

        let action: NativeMigrationAction
        guard [.older, .equal].contains(VersionComparator.compare(installedVersion, release.recommendedVersion)) else {
            return .needsVerification(reason: "The installed version is newer than, or cannot be compared with, the reviewed native release. Check the exact release with the vendor.")
        }
        switch VersionComparator.compare(
            installedVersion,
            release.minimumNativeVersion
        ) {
        case .older:
            action = .update
        case .equal, .newer:
            action = .reinstall
        case .incomparable:
            action = .reviewVersions
        }

        return .nativeReleaseAvailable(
            ProductArchitectureUpgrade(
                version: release.recommendedVersion,
                action: action,
                formats: availableFormats,
                sourceURL: release.sourceURL,
                checkedOn: release.checkedOn
            )
        )
    }

    private static func matches(
        _ product: NormalizedPluginProduct,
        release: ArchitectureSupportRecord
    ) -> Bool {
        let identifiers = product.bundles.compactMap(\.bundleIdentifier)
        guard release.vendorIdentifierPrefixes.contains(where: { prefix in
            identifiers.count == product.bundles.count && identifiers.allSatisfy({
                $0.lowercased().hasPrefix(prefix.lowercased())
            })
        }) else {
            return false
        }

        let productKey = canonicalName(product.name)
        if release.exactProductAliases.contains(where: {
            canonicalName($0) == productKey
        }) {
            return true
        }
        return release.productNamePrefixes.contains {
            productKey.hasPrefix(canonicalName($0))
        }
    }

    private static func canonicalName(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }


}

public enum ReviewedArchitectureSupportCatalogue {
    /// Compatibility accessor. Native-release claims require explicit reviewed input.
    public static var bundled: [ArchitectureSupportRecord] { [] }
}
