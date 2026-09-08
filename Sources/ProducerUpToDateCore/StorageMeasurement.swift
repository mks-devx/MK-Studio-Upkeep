// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Logical sizes of the scanned software bundles, not expected reclaimable disk space.
/// No contents are read, no symlinks are followed, and hard-linked files count once.
public enum StorageMeasurement {
    public struct Result: Sendable {
        public let bytes: Int64
        public let inspectedEntries: Int
        public let incomplete: Bool
    }
    public static func measure(_ roots: [URL], limit: Int = 250_000) throws -> Result {
        try Task.checkCancellation()
        var bytes: Int64 = 0
        var count = 0
        var incomplete = false
        var visited = Set<String>()
        var files = Set<String>()
        let paths = Array(Set(roots.map { $0.standardizedFileURL })).sorted { $0.path < $1.path }
        for root in paths {
            try Task.checkCancellation()
            guard root.isFileURL, root.path == root.resolvingSymlinksInPath().path,
                  let rootInfo = try? FileManager.default.attributesOfItem(atPath: root.path),
                  rootInfo[.type] as? FileAttributeType == .typeDirectory else { incomplete = true; continue }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [],
                errorHandler: { _, _ in incomplete = true; return true }) else { incomplete = true; continue }
            for case let file as URL in enumerator {
                try Task.checkCancellation()
                guard count < limit else { return Result(bytes: bytes, inspectedEntries: count, incomplete: true) }
                guard visited.insert(file.standardizedFileURL.path).inserted else { enumerator.skipDescendants(); continue }
                count += 1
                guard let info = try? FileManager.default.attributesOfItem(atPath: file.path) else { incomplete = true; continue }
                if info[.type] as? FileAttributeType == .typeSymbolicLink { enumerator.skipDescendants(); continue }
                if enumerator.level > 64 { incomplete = true; enumerator.skipDescendants(); continue }
                guard info[.type] as? FileAttributeType == .typeRegular else { continue }
                let identity = "\(info[.systemNumber] ?? ""):\(info[.systemFileNumber] ?? file.path)"
                guard files.insert(identity).inserted else { continue }
                let size = (info[.size] as? NSNumber)?.int64Value ?? 0
                let sum = bytes.addingReportingOverflow(max(0, size))
                guard !sum.overflow else { return Result(bytes: bytes, inspectedEntries: count, incomplete: true) }
                bytes = sum.partialValue
            }
        }
        return Result(bytes: bytes, inspectedEntries: count, incomplete: incomplete)
    }
}
