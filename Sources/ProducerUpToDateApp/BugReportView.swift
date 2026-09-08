// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

struct BugReportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var includeDiagnostics = false
    @State private var message: String?
    private var preview: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let diagnostics = BugReportDraft.Diagnostics(appVersion: "\(version) (\(build))",
            system: ProcessInfo.processInfo.operatingSystemVersionString, processor: MacArchitecture.current.processor.rawValue,
            pluginFiles: model.currentReport?.records.count ?? 0, dawApplications: model.installedDAWs.count,
            inaccessibleLocations: model.currentReport?.inaccessibleLocationCount ?? 0, scanPerformed: model.currentReport != nil)
        return BugReportDraft.body(description: description, diagnostics: includeDiagnostics ? diagnostics : nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Report a bug").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Describe what happened, what you expected and how to reproduce it. Remove private details, licence keys and file paths from your text.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $description).frame(height: 100).border(.quaternary)
                .accessibilityLabel("Bug description and steps to reproduce")
            Toggle("Include app and macOS versions, processor type and scan counts", isOn: $includeDiagnostics)
            Text("Report preview").font(.headline)
            ScrollView { Text(preview).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(minHeight: 100, maxHeight: 170).padding(8).border(.quaternary)
            Text("Opening the form sends this preview to GitHub in your browser. Nothing is submitted automatically. You need a GitHub account with access to this repository.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Report a security vulnerability privately", destination: URL(string: "https://github.com/mks-devx/MK-Studio-Upkeep/security/policy")!)
                .font(.caption)
            HStack {
                Button("Copy report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(preview, forType: .string)
                    message = "Report copied."
                }
                Spacer()
                Button("Open GitHub report form") {
                    if let url = BugReportDraft.formURL(body: preview), !NSWorkspace.shared.open(url) {
                        message = "Couldn’t open your browser. Copy the report and open GitHub manually."
                    }
                }.disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || BugReportDraft.formURL(body: preview) == nil)
            }
            if BugReportDraft.formURL(body: preview) == nil {
                Text("This report is too long for a prefilled form. Copy it, then paste it into a new GitHub issue.").font(.caption)
                Link("Open a blank GitHub issue", destination: URL(string: "https://github.com/mks-devx/MK-Studio-Upkeep/issues/new")!)
            }
            if let message { Text(message).font(.caption) }
        }.padding(24).frame(width: 580)
    }
}
