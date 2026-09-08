// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Size of a bundle on disk: the sum of its regular files. Links are not followed and the walk
/// is bounded, so a hostile bundle cannot turn a size lookup into a hang.
public enum BundleFootprint {
    public static let maximumEntries = 20_000

    public static func bytes(at bundle: URL) -> Int64? {
        guard let entries = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
                                                          options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        var visited = 0
        for case let url as URL in entries {
            visited += 1
            if visited > maximumEntries { return nil }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else { continue }
            if values.isSymbolicLink == true { entries.skipDescendants(); continue }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }

    public static func label(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "size unavailable"
    }
}
