// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ReleaseCheckMethod: String, Codable, Sendable {
    /// Explicit external provenance. Unrecognised retired methods fail decoding.
    case externalReference = "External reference"
}

public struct PluginReleaseRecord: Hashable, Codable, Sendable {
    public let vendorIdentifierPrefixes: [String]
    public let productAliases: [String]
    public let latestVersion: String
    public let sourceURL: URL
    public let checkedOn: String
    public var checkMethod: ReleaseCheckMethod? = nil
    public let downloadURL: URL?
    /// Links editions of one product line (for example Pro-Q 3 and Pro-Q 4). Both fields are
    /// present or both absent. A newer edition is reported separately from an update and
    /// never implies pricing or upgrade eligibility.
    public let family: String?
    public let edition: Int?

    public init(
        vendorIdentifierPrefixes: [String],
        productAliases: [String],
        latestVersion: String,
        sourceURL: URL,
        checkedOn: String,
        downloadURL: URL? = nil,
        family: String? = nil,
        edition: Int? = nil
    ) {
        self.vendorIdentifierPrefixes = vendorIdentifierPrefixes
        self.productAliases = productAliases
        self.latestVersion = latestVersion
        self.sourceURL = sourceURL
        self.checkedOn = checkedOn
        self.downloadURL = downloadURL
        self.family = family
        self.edition = edition
    }
}

/// A newer edition of the installed product line, with reviewed evidence for that edition.
public struct NewerEdition: Hashable, Codable, Sendable {
    public let name: String
    public let edition: Int
    public let latestVersion: String
    public let sourceURL: URL
    public let checkedOn: String
    public init(name: String, edition: Int, latestVersion: String, sourceURL: URL, checkedOn: String) {
        self.name = name; self.edition = edition; self.latestVersion = latestVersion
        self.sourceURL = sourceURL; self.checkedOn = checkedOn
    }
    /// Shown whenever no reviewed pricing record exists. A higher edition proves nothing about cost.
    public static let pricingNotice = "Upgrades may cost money. Check the vendor for pricing and whether you qualify."
}

public struct PluginUpdateResult: Identifiable, Hashable, Codable, Sendable {
    public let product: NormalizedPluginProduct
    public let updateState: UpdateCheckState
    public let latestVersion: String?
    public let sourceURL: URL?
    public let checkedOn: String?
    public var checkMethod: ReleaseCheckMethod? = nil
    public let reason: PluginUpdateReason?
    /// Independent of `updateState`: the installed edition is compared on its own terms.
    public let newerEdition: NewerEdition?
    /// The match rests on the user's local identity confirmation, not on the scanner's own evidence.
    public let identityConfirmedByUser: Bool

    public init(
        product: NormalizedPluginProduct,
        updateState: UpdateCheckState,
        latestVersion: String? = nil,
        sourceURL: URL? = nil,
        checkedOn: String? = nil,
        reason: PluginUpdateReason? = nil,
        newerEdition: NewerEdition? = nil,
        identityConfirmedByUser: Bool = false
    ) {
        self.product = product
        self.updateState = updateState
        self.latestVersion = latestVersion
        self.sourceURL = sourceURL
        self.checkedOn = checkedOn
        self.reason = reason
        self.newerEdition = newerEdition
        self.identityConfirmedByUser = identityConfirmedByUser
    }

    public var id: String {
        product.id
    }

    public var installedVersion: String? {
        guard product.installedVersions.count == 1 else {
            return nil
        }
        return product.installedVersions.first
    }
}

public enum PluginUpdateReason: String, Codable, Sendable {
    case identityNeedsReview, noReviewedRelease, staleEvidence, missingReleaseVersion
    case differentInstalledVersions, installedVersionAhead, incomparableVersions

    public var label: String {
        switch self {
        case .identityNeedsReview: "Identity unconfirmed"
        case .noReviewedRelease: "Not in catalogue"
        case .staleEvidence: "Evidence expired"
        case .missingReleaseVersion: "Version missing"
        case .differentInstalledVersions: "Versions differ"
        case .installedVersionAhead: "Newer than catalogue"
        case .incomparableVersions: "Cannot compare"
        }
    }

    public var detail: String {
        switch self {
        case .identityNeedsReview: "We couldn’t tie these files to one product. They stay listed, and you can confirm the identity in the product details."
        case .noReviewedRelease: "No reviewed release covers this product yet. That doesn’t mean it is up to date."
        case .staleEvidence: "The release information is more than 30 days old. Check the official source."
        case .missingReleaseVersion: "One of the installed files has no readable version, only a build number, so it can’t be compared."
        case .differentInstalledVersions: "Your installed formats report different versions. Check each copy before updating."
        case .installedVersionAhead: "Your version is newer than the reviewed release, so we can’t call it current or suggest a change."
        case .incomparableVersions: "The installed and vendor version labels can’t be compared reliably. Check with the vendor."
        }
    }
}

public extension PluginUpdateResult {
    /// Route-aware label; see `displayLabel(route:)`.
    var resultLabel: String { displayLabel(route: route) }
}

/// Counts evaluated products, independently of search and sidebar filters.
public struct PluginUpdateCoverage: Equatable, Sendable {
    public let total: Int
    public let updates: Int
    public let current: Int
    /// Products with a newer edition on record. Counted separately from updates.
    public let upgrades: Int
    /// Not compared, but a vendor manager owns their updates: an actionable route, not a gap.
    public let managed: Int
    /// Not compared; a reviewed official page is the route.
    public let websiteOnly: Int
    /// Not compared; the user can confirm the product identity locally.
    public let identityUnconfirmed: Int
    public var compared: Int { updates + current }
    public var unresolved: Int { total - compared }
    /// Nothing actionable beyond the inventory itself.
    public var unrouted: Int { total - compared - managed - websiteOnly - identityUnconfirmed }

    public init(results: [PluginUpdateResult]) {
        total = results.count
        updates = results.filter { $0.updateState == .updateAvailable }.count
        current = results.filter { $0.updateState == .current }.count
        upgrades = results.filter { $0.newerEdition != nil }.count
        let routes = results.filter { $0.latestVersion == nil }.map(\.route)
        managed = routes.filter { if case .manager = $0 { return true }; return false }.count
        websiteOnly = routes.filter { if case .website = $0 { return true }; return false }.count
        identityUnconfirmed = routes.filter { $0 == .identityUnconfirmed }.count
    }
}

public enum ReviewedPluginCatalogue {
    /// Compatibility accessor. Release comparisons require explicit input; no catalogue ships.
    public static var bundled: [PluginReleaseRecord] { [] }
}

public extension PluginReleaseRecord {
    var catalogueID: String { (vendorIdentifierPrefixes.first ?? "") + ":" + (productAliases.first ?? "") }
}
