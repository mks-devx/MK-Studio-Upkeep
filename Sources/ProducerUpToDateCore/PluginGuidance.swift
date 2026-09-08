// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Local findings remain available even when product grouping cannot support
/// vendor-release claims. No finding here establishes that an update exists.
public enum PluginGuidance {
    public static func versionsDiffer(_ product: NormalizedPluginProduct) -> Bool {
        let versions = product.bundles.compactMap(\.displayVersion)
        guard let first = versions.first else { return false }
        return versions.dropFirst().contains { other in
            first != other && VersionComparator.compare(
                VersionComparator.releaseValue(first) ?? first,
                VersionComparator.releaseValue(other) ?? other
            ) != .equal
        }
    }

    public static func intelOnlyBundles(_ product: NormalizedPluginProduct) -> [PluginBundleRecord] {
        product.bundles.filter { InstalledArchitecture.classify($0.architectures) == .intel64 }
    }

    /// Describe files individually before falling back to the combined architectures.
    public static func intelCopySummary(_ product: NormalizedPluginProduct) -> String? {
        let copies = intelOnlyBundles(product)
        guard !copies.isEmpty else { return nil }
        return copies.count == product.bundles.count ? "Intel-only" : "Mixed · Intel-only copies"
    }

    public static func intelCopyFormats(_ product: NormalizedPluginProduct) -> String {
        Set(intelOnlyBundles(product).map(\.format.rawValue)).sorted().joined(separator: " + ")
    }

    public static func identityExplanation(_ product: NormalizedPluginProduct) -> String? {
        guard product.requiresVerification else { return nil }
        if product.matchEvidence.contains(where: { $0.reason == .multiComponentContainer }) {
            return "One or more files declare multiple plugin components. These can be variants of one product, but the scanner cannot confirm their relationship yet."
        }
        if product.matchEvidence.contains(where: { $0.reason == .missingVendorInferred }) {
            return "Vendor information is missing from one or more files. Their names alone cannot establish a reliable product match."
        }
        return "The available file identifiers do not establish a reliable product match. The individual files and their locally detected details are listed below."
    }
}
