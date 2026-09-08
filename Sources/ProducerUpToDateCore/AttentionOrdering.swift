// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Orders the Needs Attention list so the reason comes first: highest severity, then one
/// issue kind at a time, then vendor and name. Presentation only; no issue is added or hidden.
public enum AttentionOrdering {
    /// The issue a row should lead with: highest severity, ties broken by title for stability.
    public static func primaryIssue(of product: NormalizedPluginProduct) -> ScanIssue? {
        product.issues.min { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public static func ordered(_ products: [NormalizedPluginProduct]) -> [NormalizedPluginProduct] {
        products.sorted { lhs, rhs in
            let left = primaryIssue(of: lhs), right = primaryIssue(of: rhs)
            let leftSeverity = left?.severity ?? .information, rightSeverity = right?.severity ?? .information
            if leftSeverity != rightSeverity { return leftSeverity > rightSeverity }
            let kind = (left?.title ?? "").localizedStandardCompare(right?.title ?? "")
            if kind != .orderedSame { return kind == .orderedAscending }
            let vendor = (lhs.vendor ?? "").localizedStandardCompare(rhs.vendor ?? "")
            if vendor != .orderedSame { return vendor == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Distinct issue titles present, in list order, with product counts for a filter control.
    public static func issueKinds(in products: [NormalizedPluginProduct]) -> [(title: String, count: Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for product in ordered(products) {
            for title in Set(product.issues.map(\.title)) {
                if counts[title] == nil { order.append(title) }
                counts[title, default: 0] += 1
            }
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }
}
