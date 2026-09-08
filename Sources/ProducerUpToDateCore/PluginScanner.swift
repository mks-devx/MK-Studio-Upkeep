// SPDX-License-Identifier: BUSL-1.1
import Foundation

public struct PluginScanner: Sendable {
    /// Plug-in folders are shallow. Deeper trees are skipped and very large ones reported incomplete.
    static let maximumDepth = 6
    static let maximumEntriesPerLocation = 100_000
    private let metadataReader: BundleMetadataReader

    public init(metadataReader: BundleMetadataReader = BundleMetadataReader()) {
        self.metadataReader = metadataReader
    }

    public func scan(
        configuration: ScanConfiguration = .standard
    ) throws -> ScanReport {
        let startedAt = Date()
        var records: [PluginBundleRecord] = []
        var locationResults: [ScanLocationResult] = []
        var seenPaths = Set<String>()

        for location in configuration.locations {
            try Task.checkCancellation()

            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: location.url.path,
                isDirectory: &isDirectory
            )
            guard exists, isDirectory.boolValue else {
                locationResults.append(
                    ScanLocationResult(
                        location: location,
                        wasAccessible: true,
                        discoveredCount: 0,
                        errorDescription: "Folder not present or not a directory; no files scanned."
                    )
                )
                continue
            }

            guard FileManager.default.isReadableFile(atPath: location.url.path) else {
                locationResults.append(
                    ScanLocationResult(
                        location: location,
                        wasAccessible: false,
                        discoveredCount: 0,
                        errorDescription: "The location is not readable."
                    )
                )
                continue
            }

            var enumerationFailed = false
            var depthLimited = false
            var itemLimited = false
            guard let enumerator = FileManager.default.enumerator(
                at: location.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in enumerationFailed = true; return true }
            ) else {
                locationResults.append(
                    ScanLocationResult(
                        location: location,
                        wasAccessible: false,
                        discoveredCount: 0,
                        errorDescription: "The location could not be enumerated."
                    )
                )
                continue
            }

            var discoveredCount = 0
            var visited = 0
            for case let candidate as URL in enumerator {
                try Task.checkCancellation()
                visited += 1
                // Bound traversal, but inspect a bundle already found at the boundary.
                if visited > Self.maximumEntriesPerLocation { itemLimited = true; break }
                let candidateExtension = candidate.pathExtension.lowercased()
                if enumerator.level > Self.maximumDepth && candidateExtension != location.format.pathExtension {
                    if (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        depthLimited = true
                    }
                    enumerator.skipDescendants()
                    continue
                }
                if PluginFormat.allCases.contains(where: { $0.pathExtension == candidateExtension }) {
                    enumerator.skipDescendants()
                }

                guard candidateExtension
                    == location.format.pathExtension
                else {
                    continue
                }

                enumerator.skipDescendants()
                guard let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let pathKey = candidate.standardizedFileURL.path
                guard seenPaths.insert(pathKey).inserted else {
                    continue
                }

                records.append(
                    metadataReader.read(
                        bundleURL: candidate,
                        format: location.format
                    )
                )
                discoveredCount += 1
            }

            locationResults.append(
                ScanLocationResult(
                    location: location,
                    wasAccessible: !enumerationFailed && !depthLimited && !itemLimited,
                    discoveredCount: discoveredCount,
                    errorDescription: {
                        var reasons: [String] = []
                        if enumerationFailed { reasons.append("Some folders could not be read.") }
                        if depthLimited { reasons.append("Some nested folders exceeded the search depth and were not searched.") }
                        if itemLimited { reasons.append("The search stopped at its item limit.") }
                        return reasons.isEmpty ? nil : reasons.joined(separator: " ") + " This location is incomplete."
                    }()
                )
            )
        }

        records.sort {
            let vendorComparison = ($0.vendor ?? "").localizedStandardCompare(
                $1.vendor ?? ""
            )
            if vendorComparison != .orderedSame {
                return vendorComparison == .orderedAscending
            }

            let nameComparison = $0.name.localizedStandardCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.format.rawValue < $1.format.rawValue
        }

        return ScanReport(
            startedAt: startedAt,
            finishedAt: Date(),
            records: records,
            locations: locationResults
        )
    }
}
