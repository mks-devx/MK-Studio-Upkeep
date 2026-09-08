// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum PluginUpdateOptions {
    /// Official destinations are routes, not release comparisons.
    public static func label(for product: NormalizedPluginProduct) -> String { ProductDestinations.plugin(product)?.label ?? "Website not identified" }
}
