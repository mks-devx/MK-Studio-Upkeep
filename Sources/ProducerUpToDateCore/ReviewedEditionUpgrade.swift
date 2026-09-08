// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// A reviewed edition relationship, never a latest-release comparison or price promise.
public struct ReviewedEditionUpgrade: Sendable {
    public let name: String
    public let url: URL
    public let reviewedOn: String
    public static func matching(_ product: NormalizedPluginProduct, installedProducts: [NormalizedPluginProduct] = [], now: Date = Date()) -> Self? {
        guard !product.requiresVerification, let date = EvidenceFreshness.date("2026-09-08"),
              (0..<180 * 86_400).contains(now.timeIntervalSince(date)),
              !product.bundles.isEmpty else { return nil }
        let name = product.name.lowercased().filter { $0.isLetter || $0.isNumber }
        func matches(_ prefix: String, major: Int) -> Bool {
            product.bundles.allSatisfy {
                $0.bundleIdentifier?.lowercased().hasPrefix(prefix) == true &&
                $0.displayVersion.flatMap { VersionComparator.parse($0)?.numbers.first } == major
            }
        }
        func alreadyInstalled(prefix: String, names: [String], major: Int) -> Bool {
            installedProducts.contains { other in
                names.contains(other.name.lowercased().filter { $0.isLetter || $0.isNumber }) &&
                !other.bundles.isEmpty && other.bundles.allSatisfy {
                    $0.bundleIdentifier?.lowercased().hasPrefix(prefix) == true &&
                    $0.displayVersion.flatMap { VersionComparator.parse($0)?.numbers.first } == major
                }
            }
        }
        if ["shaperbox2", "cableguysshaperbox2"].contains(name), matches("de.cableguys.", major: 2) {
            guard !alreadyInstalled(prefix: "de.cableguys.", names: ["shaperbox3", "cableguysshaperbox3"], major: 3) else { return nil }
            return .init(name: "ShaperBox 3", url: URL(string: "https://www.cableguys.com/shaperbox")!, reviewedOn: "2026-09-08")
        }
        if ["proq3", "fabfilterproq3"].contains(name), matches("com.fabfilter.pro-q.", major: 3) {
            guard !alreadyInstalled(prefix: "com.fabfilter.pro-q.", names: ["proq4", "fabfilterproq4"], major: 4) else { return nil }
            return .init(name: "FabFilter Pro-Q 4", url: URL(string: "https://www.fabfilter.com/help/pro-q/support/upgrading")!, reviewedOn: "2026-09-08")
        }
        return nil
    }
}
