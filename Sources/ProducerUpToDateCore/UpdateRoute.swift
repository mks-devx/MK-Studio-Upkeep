// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Where a product's update information legitimately comes from. A route is the honest
/// answer for every product, even when no version comparison is possible.
public enum UpdateRoute: Hashable, Sendable {
    /// A reviewed catalogue record matched the product (compared, or comparable with a stated reason).
    case catalogue
    /// The vendor's own manager application owns updates for this vendor line.
    case manager(ManagerDefinition)
    /// A reviewed official page exists; the user checks it in the browser.
    case website(URL)
    /// The detected files do not establish one product yet; the user can confirm the identity locally.
    case identityUnconfirmed
    /// No catalogue record, manager or reviewed page. Not a claim that the product is current.
    case none

    public var managerName: String? { if case let .manager(definition) = self { return definition.name }; return nil }
}

public enum UpdateRouteResolver {
    public static func route(for result: PluginUpdateResult) -> UpdateRoute {
        if result.latestVersion != nil { return .catalogue }
        let identifiers = result.product.bundles.compactMap(\.bundleIdentifier)
        if identifiers.count == result.product.bundles.count, let manager = ManagerDefinition.matching(identifiers: identifiers) {
            return .manager(manager)
        }
        if result.reason == .identityNeedsReview { return .identityUnconfirmed }
        let websites = Set(result.product.bundles.flatMap { $0.declaredLinks ?? [] }.filter { $0.kind == .website }.map(\.url))
        if websites.count == 1, let url = websites.first { return .website(url) }
        return .none
    }
}

public extension PluginUpdateResult {
    /// Plain-language state, shared vocabulary with DAW states. Never claims currency without evidence.
    func displayLabel(route: UpdateRoute) -> String {
        switch updateState {
        case .updateAvailable: return "Update available"
        case .current: return "Matches listed version"
        case .unavailable: return reason?.label ?? "Could not verify"
        case .notChecked:
            switch route {
            case .catalogue: return reason?.label ?? "Not checked"
            case let .manager(definition): return "Managed by \(definition.name)"
            case .website: return "Check vendor site"
            case .identityUnconfirmed: return "Identity unconfirmed"
            case .none: return reason?.label ?? "Not in catalogue"
            }
        }
    }
    var route: UpdateRoute { UpdateRouteResolver.route(for: self) }
}

/// The user's own statement that a set of detected files is one catalogued product. Stored on
/// this Mac only, marked as confirmed by the user, never sent anywhere, never edits the catalogue.
public struct IdentityConfirmations: Codable, Sendable, Equatable {
    public static let maximumEntries = 2_000
    public static let maximumBytes = 262_144
    public private(set) var records: [String: String]

    public init(records: [String: String] = [:]) { self.records = records }

    public func catalogueID(for productID: String) -> String? { records[productID] }

    public mutating func confirm(productID: String, catalogueID: String) throws {
        guard !productID.isEmpty, !catalogueID.isEmpty, productID.count <= 128, catalogueID.count <= 256,
              records.count < Self.maximumEntries || records[productID] != nil else { throw CatalogueError.invalidData }
        records[productID] = catalogueID
    }

    public mutating func remove(productID: String) { records.removeValue(forKey: productID) }

    /// Only records from the same vendor line as every detected file may be chosen. Cross-vendor
    /// confirmation is refused so a user cannot accidentally compare unrelated products.
    public static func candidates(for product: NormalizedPluginProduct, in catalogue: [PluginReleaseRecord]) -> [PluginReleaseRecord] {
        let identifiers = product.bundles.compactMap(\.bundleIdentifier).map { $0.lowercased() }
        guard !identifiers.isEmpty, identifiers.count == product.bundles.count else { return [] }
        return catalogue.filter { record in
            record.vendorIdentifierPrefixes.contains { prefix in identifiers.allSatisfy { $0.hasPrefix(prefix.lowercased()) } }
        }.sorted { ($0.productAliases.first ?? "").localizedStandardCompare($1.productAliases.first ?? "") == .orderedAscending }
    }

    public static func load(from url: URL) -> IdentityConfirmations {
        guard let data = SafeFileAccess.data(at: url, maximumBytes: maximumBytes), JSONDepth.isWithinLimit(data),
              let value = try? JSONDecoder().decode(IdentityConfirmations.self, from: data),
              value.records.count <= maximumEntries,
              value.records.allSatisfy({ !$0.key.isEmpty && !$0.value.isEmpty && $0.key.count <= 128 && $0.value.count <= 256 }) else { return IdentityConfirmations() }
        return value
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw CatalogueError.invalidData }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Why a product has no version comparison, as one line a user can act on. Every product
/// without a comparison gets exactly one reason, so the Not Checked list can be sorted by it.
public enum NotCheckedReason: String, CaseIterable, Sendable {
    case vendorApp = "Updates come from a vendor app"
    case checkVendorSite = "Check the vendor site"
    case confirmIdentity = "Confirm the product identity"
    case fileWithoutIdentifier = "A file has no bundle identifier"
    case notInCatalogue = "Not in the catalogue yet"

    public var detail: String {
        switch self {
        case .vendorApp: "The vendor's own app delivers updates for this product line. Open it to check."
        case .checkVendorSite: "A reviewed official page exists for this product; the app does not read it. Open it in your browser."
        case .confirmIdentity: "The files did not tie to one catalogued product. Product details let you confirm which one they are."
        case .fileWithoutIdentifier: "One of the installed files declares no bundle identifier, so it cannot be attributed to a vendor or a catalogue entry."
        case .notInCatalogue: "No reviewed release exists for this product. Coverage grows as entries are added; nothing is wrong with the plug-in."
        }
    }

    /// Ordered reason counts for a set of results, most common first.
    public static func kinds(in results: [PluginUpdateResult]) -> [(title: String, count: Int)] {
        var counts: [NotCheckedReason: Int] = [:]
        for result in results { if let reason = result.notCheckedReason { counts[reason, default: 0] += 1 } }
        return allCases.compactMap { reason in counts[reason].map { (reason.rawValue, $0) } }.sorted { $0.count > $1.count }
    }
}

public extension PluginUpdateResult {
    /// Nil when the product was compared against the catalogue.
    var notCheckedReason: NotCheckedReason? {
        guard latestVersion == nil else { return nil }
        switch route {
        case .catalogue: return nil
        case .manager: return .vendorApp
        case .website: return .checkVendorSite
        case .identityUnconfirmed: return .confirmIdentity
        case .none: return product.bundles.contains { $0.bundleIdentifier == nil } ? .fileWithoutIdentifier : .notInCatalogue
        }
    }
}
