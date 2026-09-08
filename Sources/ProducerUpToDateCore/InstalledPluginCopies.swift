// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Presentation groups preserve every distinct file without merging product editions.
public struct InstalledPluginCopies: Identifiable, Sendable {
    public let format: PluginFormat
    public let copies: [PluginBundleRecord]
    public var id: PluginFormat { format }

    public static func groups(for product: NormalizedPluginProduct) -> [InstalledPluginCopies] {
        let files = PluginBundleRecord.distinctInstalledCopies(product.bundles)
        return PluginFormat.allCases.compactMap { format in
            let copies = files.filter { $0.format == format }.sorted { $0.path.path < $1.path.path }
            return copies.isEmpty ? nil : InstalledPluginCopies(format: format, copies: copies)
        }
    }

    public static func locationLabel(for path: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let value = path.standardizedFileURL.path
        let userRoot = home.appendingPathComponent("Library/Audio/Plug-Ins").standardizedFileURL.path + "/"
        if value.hasPrefix(userRoot) { return "Your account" }
        if value.hasPrefix("/Library/Audio/Plug-Ins/") { return "All users" }
        return "Other location"
    }
}
