// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Writes the inventory the user is looking at to a file of their choosing. Runs entirely on
/// the Mac; nothing is uploaded. Paths are optional and, when included, have the home folder
/// replaced by "~" so the account name never appears.
public enum InventoryExport {
    public struct Row: Equatable, Sendable {
        public let kind: String
        public let name: String
        public let vendor: String
        public let installedVersion: String
        public let formats: String
        public let architectures: String
        public let result: String
        public let latestReviewed: String
        public let reason: String
        public let paths: [String]
    }

    public static func rows(plugins: [PluginUpdateResult], daws: [InstalledDAWRecord],
                            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, localOnly: Bool = false) -> [Row] {
        let home = homeDirectory.standardizedFileURL.path
        func tidy(_ path: URL) -> String {
            let value = path.standardizedFileURL.path
            return value.hasPrefix(home + "/") ? "~" + value.dropFirst(home.count) : value
        }
        let pluginRows = plugins.map { result in
            let product = result.product
            let versions = Array(Set(product.bundles.compactMap(\.displayVersion))).sorted()
            return Row(kind: "Plugin", name: product.name, vendor: product.vendor ?? "",
                installedVersion: versions.joined(separator: " / "),
                formats: product.bundles.map(\.format.rawValue).sorted().joined(separator: " + "),
                architectures: architectureText(product.bundles.flatMap(\.architectures)),
                result: localOnly ? PluginUpdateOptions.label(for: product) : result.resultLabel, latestReviewed: localOnly ? "" : result.latestVersion ?? "",
                reason: localOnly ? "" : result.notCheckedReason?.rawValue ?? "",
                paths: product.bundles.map { tidy($0.path) }.sorted())
        }
        let dawRows = daws.map { daw in
            Row(kind: "DAW", name: daw.name, vendor: daw.vendor, installedVersion: daw.displayVersion ?? "",
                formats: "", architectures: architectureText(daw.architectures),
                result: localOnly ? "Check with developer or App Store" : daw.updateState == .updateAvailable ? "Update available" : daw.updateState == .current ? "Up to date" : "Not checked",
                latestReviewed: localOnly ? "" : daw.latestVersion ?? "", reason: "", paths: [tidy(daw.path)])
        }
        return (pluginRows + dawRows).sorted { ($0.kind, $0.vendor.lowercased(), $0.name.lowercased()) < ($1.kind, $1.vendor.lowercased(), $1.name.lowercased()) }
    }

    static func architectureText(_ architectures: [BinaryArchitecture]) -> String {
        let set = Set(architectures)
        if set.contains(.arm64) && set.contains(.x86_64) { return "Apple Silicon + Intel" }
        if set == [.arm64] { return "Apple Silicon" }
        if set == [.x86_64] { return "Intel" }
        return set.isEmpty ? "" : "Other"
    }

    public static func csv(_ rows: [Row], includePaths: Bool, localOnly: Bool = false) -> String {
        var header = ["Type", "Name", "Vendor", "Installed version", "Formats", "Architecture", "Update result", "Latest reviewed version", "Why not checked"]
        if localOnly { header = Array(header.prefix(6)) + ["Update options"] }
        if includePaths { header.append("Paths") }
        func cell(_ value: String) -> String {
            // Spreadsheet applications interpret formula prefixes even inside CSV quotes.
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.first.map { "=+-@".contains($0) } == true ? "'" + value : value
            let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
            return needsQuotes ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
        }
        let lines = rows.map { row in
            var cells = [row.kind, row.name, row.vendor, row.installedVersion, row.formats, row.architectures, row.result, row.latestReviewed, row.reason]
            if localOnly { cells = Array(cells.prefix(7)) }
            if includePaths { cells.append(row.paths.joined(separator: "; ")) }
            return cells.map(cell).joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + lines).joined(separator: "\n") + "\n"
    }

    public static func text(_ rows: [Row], includePaths: Bool, exportedOn: Date = Date()) -> String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        var lines = ["MK Studio Upkeep inventory · \(formatter.string(from: exportedOn))",
                     "\(rows.filter { $0.kind == "Plugin" }.count) plugin products · \(rows.filter { $0.kind == "DAW" }.count) DAWs · exported locally, nothing was sent anywhere", ""]
        for row in rows {
            var line = "\(row.kind): \(row.name)"
            if !row.vendor.isEmpty { line += " — \(row.vendor)" }
            if !row.installedVersion.isEmpty { line += " · \(row.installedVersion)" }
            if !row.formats.isEmpty { line += " · \(row.formats)" }
            if !row.architectures.isEmpty { line += " · \(row.architectures)" }
            line += " · \(row.result)"
            if !row.latestReviewed.isEmpty { line += " (reviewed: \(row.latestReviewed))" }
            if !row.reason.isEmpty { line += " · \(row.reason)" }
            lines.append(line)
            if includePaths { lines += row.paths.map { "    \($0)" } }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
