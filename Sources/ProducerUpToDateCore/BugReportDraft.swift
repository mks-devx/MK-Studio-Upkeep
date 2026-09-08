// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Only explicitly supplied text and optional aggregate diagnostics enter a report.
/// No paths, inventory records, account names, logs or credentials are read.
public enum BugReportDraft {
    public struct Diagnostics: Sendable {
        public let appVersion: String
        public let system: String
        public let processor: String
        public let pluginFiles: Int
        public let dawApplications: Int
        public let inaccessibleLocations: Int
        public let scanPerformed: Bool
        public init(appVersion: String, system: String, processor: String, pluginFiles: Int, dawApplications: Int, inaccessibleLocations: Int, scanPerformed: Bool = true) {
            self.appVersion = appVersion; self.system = system; self.processor = processor
            self.pluginFiles = max(0, pluginFiles); self.dawApplications = max(0, dawApplications)
            self.inaccessibleLocations = max(0, inaccessibleLocations)
            self.scanPerformed = scanPerformed
        }
    }
    public static func body(description: String, diagnostics: Diagnostics?) -> String {
        var text = "## What happened\n\n" + description
        if let d = diagnostics {
            func safe(_ value: String) -> String { DisplaySanitiser.sanitise(value, maximumLength: 100) ?? "Unknown" }
            text += "\n\n## Optional diagnostics\n\nApp: \(safe(d.appVersion))\nSystem: \(safe(d.system))\nProcessor: \(safe(d.processor))"
            if d.scanPerformed {
                text += "\nPlugin files found: \(d.pluginFiles)\nDAW applications found: \(d.dawApplications)\nPlugin locations not fully scanned: \(d.inaccessibleLocations)"
            } else {
                text += "\nScan: No completed scan in this session"
            }
        }
        return text
    }
    /// The report is sent to GitHub when this URL is opened, before issue submission.
    /// Refuse overlong URLs rather than silently lose the user's text.
    public static func formURL(body: String) -> URL? {
        guard body.utf8.count <= 6000 else { return nil }
        var components = URLComponents(string: "https://github.com/mks-devx/MK-Studio-Upkeep/issues/new")!
        components.queryItems = [URLQueryItem(name: "template", value: "bug_report.md"), URLQueryItem(name: "body", value: body)]
        guard let url = components.url, url.absoluteString.utf8.count <= 7500 else { return nil }
        return url
    }
}
