// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Version-free, reviewed developer destinations. A vendor route never establishes
/// the latest release, edition eligibility, purchase ownership or compatibility.
public struct ProductDestination: Sendable, Equatable {
    public let url: URL
    public let label: String
    public let referenceURL: URL
    public let reviewedOn: String
}
public enum ProductDestinations {
    private struct Developer {
        let prefixes: [String]
        let url: String
        let referenceURL: String
        let reviewedOn: String
    }
    private static let developers: [Developer] = [
        .init(prefixes: ["com.fabfilter."], url: "https://www.fabfilter.com/download", referenceURL: "https://www.fabfilter.com/download", reviewedOn: "2026-09-13"),
        .init(prefixes: ["de.cableguys."], url: "https://www.cableguys.com/products", referenceURL: "https://www.cableguys.com/products", reviewedOn: "2026-09-13"),
        .init(prefixes: ["com.valhalladsp."], url: "https://valhalladsp.com/demos-downloads/", referenceURL: "https://valhalladsp.com/demos-downloads/", reviewedOn: "2026-09-13"),
        .init(prefixes: ["com.tokyodawnlabs."], url: "https://www.tokyodawn.net/tokyo-dawn-labs/", referenceURL: "https://www.tokyodawn.net/tokyo-dawn-labs/", reviewedOn: "2026-09-13"),
        .init(prefixes: ["com.u-he."], url: "https://u-he.com/products/", referenceURL: "https://u-he.com/products/", reviewedOn: "2026-09-13"),
        .init(prefixes: ["com.d16group."], url: "https://d16.pl/downloads", referenceURL: "https://d16.pl/downloads", reviewedOn: "2026-09-13")
    ]
    static var reviewEvidenceIsComplete: Bool {
        developers.allSatisfy { developer in
            guard let reference = URL(string: developer.referenceURL) else { return false }
            return OfficialLinkReview.isComplete(referenceURL: reference, reviewedOn: developer.reviewedOn)
        }
    }
    public static func plugin(_ product: NormalizedPluginProduct) -> ProductDestination? {
        let ids = product.bundles.compactMap(\.bundleIdentifier)
        guard ids.count == product.bundles.count, !ids.isEmpty else { return nil }
        if let manager = ManagerDefinition.matching(identifiers: ids), let url = manager.url {
            return .init(url: url, label: "Developer website", referenceURL: manager.referenceURL, reviewedOn: manager.reviewedOn)
        }
        let matches = developers.filter { developer in ids.allSatisfy { id in developer.prefixes.contains { id.lowercased().hasPrefix($0) } } }
        guard matches.count == 1, let url = URL(string: matches[0].url),
              let referenceURL = URL(string: matches[0].referenceURL),
              OfficialLinkReview.isComplete(referenceURL: referenceURL, reviewedOn: matches[0].reviewedOn) else { return nil }
        return .init(url: url, label: "Developer website", referenceURL: referenceURL, reviewedOn: matches[0].reviewedOn)
    }
    public static func daw(_ daw: InstalledDAWRecord) -> ProductDestination? {
        guard !daw.identityIsInferred, let destination = DAWUpdateSource.reviewedDestination(for: daw.definitionID) else { return nil }
        return .init(url: destination.url, label: "Developer website", referenceURL: destination.referenceURL, reviewedOn: destination.reviewedOn)
    }
}
