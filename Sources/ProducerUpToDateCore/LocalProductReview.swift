// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum LocalReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All findings"
    case cannotRun = "Cannot run on this Mac"
    case differentVersions = "Different installed versions"
    case repeatedCopies = "Multiple copies of one format"
    case relatedEditions = "Related editions installed"
    case newerEdition = "Newer edition known"
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
    /// Suggestions only: never merges editions or identifies files as safe to delete.
    /// A number in a name is an edition only when the installed release major agrees.
    public static func relatedEditions(_ products: [NormalizedPluginProduct]) -> [String: [NormalizedPluginProduct]] {
        struct Candidate { let product: NormalizedPluginProduct; let major: Int; let key: String }
        let candidates = products.compactMap { product -> Candidate? in
            guard !product.requiresVerification, let vendor = product.vendor, !vendor.isEmpty,
                  let version = product.bundles.first?.displayVersion,
                  let parsed = VersionComparator.parse(version), parsed.channel == .stable,
                  let major = parsed.numbers.first,
                  product.bundles.allSatisfy({ $0.displayVersion.flatMap { VersionComparator.parse($0)?.numbers.first } == major }),
                  let identifier = product.bundles.first?.bundleIdentifier,
                  identifier.split(separator: ".").count >= 3 else { return nil }
            let publisher = identifier.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
            guard product.bundles.allSatisfy({ $0.bundleIdentifier?.lowercased().hasPrefix(publisher + ".") == true }) else { return nil }
            var name = displayName(product.name).lowercased()
            let regex = try! NSRegularExpression(pattern: #"(?<=[a-z ])([0-9]{1,2})(?=\s|$)"#)
            let matches = regex.matches(in: name, range: NSRange(name.startIndex..., in: name))
            guard matches.count <= 1 else { return nil }
            if let match = matches.first, let range = Range(match.range(at: 1), in: name) {
                guard Int(name[range]) == major else { return nil }
                name.removeSubrange(range)
            }
            name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return Candidate(product: product, major: major, key: vendor.lowercased() + "|" + publisher + "|" + name)
        }
        var index: [String: [NormalizedPluginProduct]] = [:]
        for group in Dictionary(grouping: candidates, by: \.key).values where Set(group.map(\.major)).count > 1 {
            for candidate in group {
                index[candidate.product.id] = group.filter { $0.major != candidate.major }.map(\.product).sorted { $0.name < $1.name }
            }
        }
        return index
    }
}
