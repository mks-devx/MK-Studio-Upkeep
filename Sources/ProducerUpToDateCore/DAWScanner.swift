// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation

public struct DAWScanner: Sendable {
    /// Application folders are shallow. Deeper trees are skipped and very large ones reported incomplete.
    static let maximumDepth = 6
    static let maximumEntriesPerRoot = 100_000
    public init() {}

    public func scan(
        configuration: DAWScanConfiguration = .standard
    ) throws -> [InstalledDAWRecord] {
        try scanReport(configuration: configuration).records
    }

    public func scanReport(configuration: DAWScanConfiguration = .standard) throws -> (records: [InstalledDAWRecord], warnings: [String], scopeNotes: [String]) {
        var warnings: [String] = []
        var scopeNotes: [String] = []
        var records: [InstalledDAWRecord] = []
        var seenPaths = Set<String>()

        for root in configuration.applicationRoots {
            try Task.checkCancellation()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                let path = DisplaySanitiser.sanitise(root.path, maximumLength: 4096) ?? "Application folder"
                warnings.append("\(path) — This application search location is not a folder.")
                continue
            }
            var skipped: [String] = []
            var depthSkipped: [String] = []
            func describe(_ url: URL, _ reason: String) -> String {
                let path = DisplaySanitiser.sanitise(url.path, maximumLength: 4096) ?? "Application folder"
                return "\(path) — \(reason)"
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    let code = (error as NSError).code
                    skipped.append(describe(url, "Could not read this location (system error \(code)). Check its permissions and whether the drive is connected."))
                    return true
                }
            ) else {
                warnings.append(describe(root, "Could not open this application folder. Check its permissions and whether the drive is connected."))
                continue
            }

            var visited = 0
            for case let candidate as URL in enumerator {
                try Task.checkCancellation()
                visited += 1
                if visited > Self.maximumEntriesPerRoot {
                    skipped.append(describe(root, "Search stopped after \(Self.maximumEntriesPerRoot) items. This folder is too large for the bounded application search; running the same scan again will not extend it."))
                    break
                }
                // The enumerator already found this entry. Inspect an app here without
                // descending into it, even at the depth boundary.
                let isApplication = candidate.pathExtension.lowercased() == "app"
                if !isApplication && enumerator.level > Self.maximumDepth {
                    if (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        depthSkipped.append(DisplaySanitiser.sanitise(candidate.path, maximumLength: 4096) ?? "Application folder")
                    }
                    enumerator.skipDescendants()
                    continue
                }
                guard isApplication else {
                    continue
                }
                enumerator.skipDescendants()
                guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { continue }

                let path = candidate.standardizedFileURL.path
                guard seenPaths.insert(path).inserted,
                      let properties = bundleProperties(at: candidate),
                      let definition = matchingDefinition(
                        bundleIdentifier: properties.bundleIdentifier,
                        applicationName: properties.applicationName,
                        definitions: configuration.definitions
                      )
                else {
                    continue
                }

                let architectures = properties.executableURL.map {
                    MachOArchitectureDetector.architectures(at: $0)
                } ?? []
                let installedFromAppStore = hasAppStoreReceipt(candidate)
                records.append(
                    InstalledDAWRecord(
                        id: stableHash(path),
                        definitionID: definition.id,
                        name: DisplaySanitiser.sanitise(candidate.deletingPathExtension().lastPathComponent)
                            ?? properties.applicationName,
                        vendor: definition.vendor,
                        bundleIdentifier: properties.bundleIdentifier,
                        displayVersion: properties.displayVersion,
                        buildVersion: properties.buildVersion,
                        path: candidate,
                        executablePath: properties.executableURL,
                        architectures: architectures,
                        identityIsInferred: !definition.bundleIdentifiers.contains(properties.bundleIdentifier ?? ""),
                        installedFromAppStore: installedFromAppStore
                    )
                )
            }
            if !depthSkipped.isEmpty {
                let paths = Set(depthSkipped).sorted()
                scopeNotes.append("\(paths.count) nested folders were not searched because each exceeds the application search depth. Running the same scan again will not extend it.\n\n" + paths.joined(separator: "\n"))
            }
            warnings.append(contentsOf: skipped)
        }

        let sorted = records.sorted {
            let nameComparison = $0.name.localizedStandardCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return $0.path.path < $1.path.path
        }
        return (sorted, warnings, scopeNotes)
    }

    /// Mac App Store installs carry Contents/_MASReceipt/receipt. Only a regular file
    /// inside the bundle counts; the receipt is not opened or validated.
    private func hasAppStoreReceipt(_ bundle: URL) -> Bool {
        let receipt = bundle.appendingPathComponent("Contents/_MASReceipt/receipt")
        guard SafeFileAccess.contained(receipt, in: bundle),
              let values = try? receipt.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func bundleProperties(at url: URL) -> (
        applicationName: String,
        bundleIdentifier: String?,
        displayVersion: String?,
        buildVersion: String?,
        executableURL: URL?
    )? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard SafeFileAccess.contained(infoURL, in: url),
              let data = SafeFileAccess.data(at: infoURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else {
            return nil
        }

        let executableName = plist["CFBundleExecutable"] as? String
        func text(_ key: String, maximumLength: Int = DisplaySanitiser.defaultMaximumLength) -> String? {
            (plist[key] as? String).flatMap { DisplaySanitiser.sanitise($0, maximumLength: maximumLength) }
        }
        return (
            applicationName: text("CFBundleDisplayName")
                ?? text("CFBundleName")
                ?? DisplaySanitiser.sanitise(url.deletingPathExtension().lastPathComponent) ?? "Application",
            bundleIdentifier: text("CFBundleIdentifier"),
            displayVersion: text("CFBundleShortVersionString", maximumLength: VersionComparator.maximumLength),
            buildVersion: text("CFBundleVersion", maximumLength: VersionComparator.maximumLength),
            executableURL: SafeFileAccess.executable(in: url, name: executableName)
        )
    }

    private func matchingDefinition(
        bundleIdentifier: String?,
        applicationName: String,
        definitions: [DAWDefinition]
    ) -> DAWDefinition? {
        // Companion/manager apps can share a product's display-name prefix.
        if bundleIdentifier == "com.reasonstudios.nautilus" { return nil }
        if let bundleIdentifier,
           let match = definitions.first(where: {
               $0.bundleIdentifiers.contains(bundleIdentifier)
           }) {
            return match
        }

        let helperPattern = #"(?i)(?:^|[\s_-])(companion|manager|installer|uninstaller|scanner|bridge|rack|plug-?in)(?:$|[\s_-])"#
        guard applicationName.range(of: helperPattern, options: .regularExpression) == nil else { return nil }
        return definitions.first { definition in
            definition.applicationNamePrefixes.contains { prefix in
                let pattern = "^" + NSRegularExpression.escapedPattern(for: prefix) + #"(?=$|[\s0-9])"#
                return applicationName.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
    }

    private func stableHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
