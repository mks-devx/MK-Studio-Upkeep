// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum LocalReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All findings"
    case cannotRun = "Cannot run on this Mac"
    case differentVersions = "Different installed versions"
    case repeatedCopies = "Multiple copies of one format"
    public var id: String { rawValue }
}
public enum LocalProductReview {
    public static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
    }
    public static func cannotRun(_ product: NormalizedPluginProduct, processor: MacProcessor) -> Bool {
        product.bundles.contains {
            let type = InstalledArchitecture.classify($0.architectures)
            return type == .legacy32 || processor == .intel && type == .appleSilicon
        }
    }
    public static func hasRepeatedFormat(_ product: NormalizedPluginProduct) -> Bool {
        Dictionary(grouping: PluginBundleRecord.distinctInstalledCopies(product.bundles), by: \.format).values.contains { $0.count > 1 }
    }
}
