// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Version-free, reviewed developer destinations. A vendor route never establishes
/// the latest release, edition eligibility, purchase ownership or compatibility.
public struct ProductDestination: Sendable, Equatable {
    public let url: URL
    public let label: String
    public let reviewedOn: String
}
public enum ProductDestinations {
    private struct Developer {
        let prefixes: [String]
        let url: String
    }
    private static let developers: [Developer] = [
        .init(prefixes: ["com.fabfilter."], url: "https://www.fabfilter.com/download"),
        .init(prefixes: ["de.cableguys."], url: "https://www.cableguys.com/products"),
        .init(prefixes: ["com.valhalladsp."], url: "https://valhalladsp.com/demos-downloads/"),
        .init(prefixes: ["com.tokyodawnlabs."], url: "https://www.tokyodawn.net/tokyo-dawn-labs/"),
        .init(prefixes: ["com.u-he."], url: "https://u-he.com/products/"),
        .init(prefixes: ["com.d16group."], url: "https://d16.pl/downloads")
    ]
    public static func plugin(_ product: NormalizedPluginProduct) -> ProductDestination? {
        let ids = product.bundles.compactMap(\.bundleIdentifier)
        guard ids.count == product.bundles.count, !ids.isEmpty else { return nil }
        if let manager = ManagerDefinition.matching(identifiers: ids), let url = manager.url {
            return .init(url: url, label: "Developer website", reviewedOn: "2026-09-08")
        }
        let matches = developers.filter { developer in ids.allSatisfy { id in developer.prefixes.contains { id.lowercased().hasPrefix($0) } } }
        guard matches.count == 1, let url = URL(string: matches[0].url) else { return nil }
        return .init(url: url, label: "Developer website", reviewedOn: "2026-09-08")
    }
    public static func daw(_ daw: InstalledDAWRecord) -> ProductDestination? {
        guard !daw.identityIsInferred, let url = DAWUpdateSource.destination(for: daw.definitionID) else { return nil }
        return .init(url: url, label: "Developer website", reviewedOn: "2026-09-08")
    }
}
