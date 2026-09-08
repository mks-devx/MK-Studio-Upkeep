// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation

public struct BundleContentsSnapshot: Sendable {
    public let paths: [String]
    public let fingerprint: String
    /// Sum of regular-file sizes inside the bundle; links and folders count nothing.
    public let totalBytes: Int64
}
public enum BundleContentsPreview {
    public static func scan(_ bundle: URL, limit: Int = 250_000) throws -> BundleContentsSnapshot {
        try Task.checkCancellation()
        var failed = false
        guard let entries = FileManager.default.enumerator(at: bundle,
            includingPropertiesForKeys: [.isSymbolicLinkKey], options: [],
            errorHandler: { _, _ in failed = true; return false }) else { throw CocoaError(.fileReadNoPermission) }
        var paths: [String] = []
        var manifest: [[String]] = []
        var totalBytes: Int64 = 0
        let prefix = bundle.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for case let url as URL in entries {
            try Task.checkCancellation()
            guard paths.count < limit else { throw CocoaError(.fileReadTooLarge) }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw CocoaError(.fileReadInvalidFileName) }
            let relative = String(path.dropFirst(prefix.count))
            paths.append(relative)
            let link = attributes[.type] as? FileAttributeType == .typeSymbolicLink
            if attributes[.type] as? FileAttributeType == .typeRegular { totalBytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0 }
            if link { entries.skipDescendants() }
            let destination = link ? try FileManager.default.destinationOfSymbolicLink(atPath: path) : ""
            manifest.append([relative, String(describing: attributes[.type] ?? ""),
                String(describing: attributes[.systemFileNumber] ?? ""), String(describing: attributes[.size] ?? ""),
                String((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0), destination])
        }
        guard !failed else { throw CocoaError(.fileReadNoPermission) }
        let bytes = try JSONEncoder().encode(manifest.sorted { $0[0] < $1[0] })
        return .init(paths: paths.sorted(), fingerprint: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), totalBytes: totalBytes)
    }
}
