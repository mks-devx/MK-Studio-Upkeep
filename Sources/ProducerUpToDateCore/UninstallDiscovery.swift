// SPDX-License-Identifier: BUSL-1.1
import Foundation

public struct UninstallFinding: Identifiable, Sendable {
    public let path: URL
    public let evidence: String
    public var softwareKind: CleanupItemKind? = nil
    public var id: String { path.path }
}
public struct UninstallDiscoveryReport: Sendable {
    public let findings: [UninstallFinding]
    public let warnings: [String]
    public let inspectedEntries: Int
}

/// Read-only, bounded associated-file discovery. A matching identifier is evidence of
/// association, never proof of exclusive ownership or permission to delete support data.
public enum UninstallDiscovery {
    public static var standardRoots: [URL] { roots(homeDirectory: FileManager.default.homeDirectoryForCurrentUser) }

    public static func roots(homeDirectory: URL) -> [URL] {
        let libraries = [homeDirectory.appendingPathComponent("Library"),
                         URL(fileURLWithPath: "/Library")]
        return libraries.flatMap { library in
            ["Preferences", "Caches", "Application Support", "Saved Application State", "LaunchAgents", "LaunchDaemons", "Audio/Plug-Ins", "Audio/MIDI Drivers", "Containers", "Group Containers", "Application Scripts", "Logs"]
                .map { library.appendingPathComponent($0) }
        } + [URL(fileURLWithPath: "/Applications"), homeDirectory.appendingPathComponent("Applications")]
    }
    public static func scan(identifiers: [String], roots: [URL] = standardRoots,
                            limit: Int = 200_000, maximumDepth: Int = 12) throws -> UninstallDiscoveryReport {
        try Task.checkCancellation()
        let ids = Set(identifiers.filter { value in
            value.split(separator: ".").count >= 3 && value.count < 256 && !value.contains("..")
                && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
        })
        guard !ids.isEmpty else { return .init(findings: [], warnings: ["No usable bundle identity; associated-file ownership cannot be checked."], inspectedEntries: 0) }
        var findings: [String: UninstallFinding] = [:]
        var warnings: [String] = []
        var inspected = 0
        var depthLimited = false
        var seen = Set<String>()
        for root in roots {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            guard root.standardizedFileURL.path == root.resolvingSymlinksInPath().path else {
                warnings.append("Skipped linked location: \(root.path)"); continue
            }
            guard let entries = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsPackageDescendants],
                errorHandler: { url, _ in warnings.append("Could not inspect \(url.path)"); return true }) else {
                warnings.append("Could not inspect \(root.path)"); continue
            }
            for case let url as URL in entries {
                try Task.checkCancellation()
                guard inspected < limit else {
                    warnings.append("Associated-file scan stopped at \(limit) entries; results are incomplete.")
                    return .init(findings: findings.values.sorted { $0.id < $1.id }, warnings: warnings, inspectedEntries: inspected)
                }
                guard seen.insert(url.standardizedFileURL.path).inserted else { continue }
                inspected += 1
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true { entries.skipDescendants(); continue }
                if entries.level > maximumDepth { depthLimited = true; entries.skipDescendants(); continue }
                let name = url.lastPathComponent
                let matches = ids.contains { id in
                    [id, id + ".plist", id + ".savedState", "." + id, "." + id + ".plist"].contains(name)
                }
                if ["component", "vst", "vst3", "clap", "app"].contains(url.pathExtension.lowercased()) {
                    entries.skipDescendants()
                    let plist = url.appendingPathComponent("Contents/Info.plist")
                    if SafeFileAccess.contained(plist, in: url), let data = SafeFileAccess.data(at: plist),
                       let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let identifier = object["CFBundleIdentifier"] as? String, ids.contains(identifier) {
                        var finding = UninstallFinding(path: url, evidence: "Exact bundle identifier in software metadata. Eligible copies require a separate safety check and explicit selection.")
                        finding.softwareKind = url.pathExtension.lowercased() == "app" ? .application : .pluginBundle
                        findings[url.path] = finding
                    }
                } else if matches {
                    findings[url.path] = .init(path: url, evidence: "Exact bundle-identifier filename match. Association only; may contain shared data, presets or licences. Preserved.")
                    if values?.isDirectory == true { entries.skipDescendants() }
                }
            }
        }
        if depthLimited { warnings.append("Some folders exceeded the search depth; results are incomplete.") }
        return .init(findings: findings.values.sorted { $0.id < $1.id }, warnings: warnings, inspectedEntries: inspected)
    }

    /// Only additional exact-ID software bundles enter the review. Associated support data
    /// never becomes removable merely because a filename resembles an identifier.
    public static func additionalSoftware(in report: UninstallDiscoveryReport, original: CleanupPlan,
                                          safety: CleanupSafety = CleanupSafety()) -> [CleanupItem] {
        guard !original.items.isEmpty, !original.items.contains(where: { $0.kind == .driverBundle }) else { return [] }
        let existing = Set(original.items.map { $0.path.standardizedFileURL.path })
        return report.findings.compactMap { finding in
            guard let kind = finding.softwareKind, !existing.contains(finding.path.standardizedFileURL.path) else { return nil }
            let item = CleanupItem(path: finding.path, kind: kind)
            return safety.validate(item) == nil ? item : nil
        }
    }
}

public enum HoldToConfirmPolicy {
    public static let duration: TimeInterval = 5
    public static func permits(start: TimeInterval, end: TimeInterval, cancelled: Bool) -> Bool {
        !cancelled && start.isFinite && end.isFinite && end - start >= duration
    }
}
