// SPDX-License-Identifier: MPL-2.0
import AppKit
import Foundation
import ProducerUpToDateCore
import SwiftUI

struct CleanupActionView: View {
    @EnvironmentObject private var model: AppModel
    let plan: CleanupPlan
    var identifiers: [String] = []
    var reviewOnly = false
    /// Extra context shown above the file list, for example what a driver is and which devices use it.
    var preface: [String] = []
    /// Called after a successful move instead of a plugin rescan, for example to rescan hardware.
    var onCompleted: (() -> Void)? = nil
    /// A red "Don’t delete this" warning shown above everything else when set.
    var criticalWarning: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var discovery: UninstallDiscoveryReport?
    @State private var discoveryTask: Task<Void, Never>?
    @State private var isDiscovering = false
    @State private var discoveryFailure: String?
    @State private var hostClosed = false
    @State private var bundleContents: [String: [String]] = [:]
    @State private var bundleSizes: [String: Int64] = [:]

    @State private var previewPlan: CleanupPlan?
    @State private var selectedIDs = Set<String>()
    private var reviewedPlan: CleanupPlan { previewPlan ?? plan }
    @State private var showsPreview = false
    @State private var resultMessage: String?
    @State private var isWorking = false
    @State private var copiedLocations = false
    @State private var showsKeptLocations = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    private var keptFindings: [UninstallFinding] {
        (discovery?.findings ?? []).filter { finding in
            !reviewedPlan.items.contains { $0.path.standardizedFileURL.path == finding.path.standardizedFileURL.path }
        }
    }
    private var keptLocationSummary: String {
        let heading = "Related files kept in their original locations. No backup was created."
        let paths = keptFindings.map { $0.path.path }.joined(separator: "\n")
        let limits = discovery?.warnings.joined(separator: "\n") ?? ""
        return [heading, paths.isEmpty ? "No related locations were identified; other files may still exist." : paths, limits]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private var removalDisabledReason: String? {
        if !TestedPlatform.removalAllowed { return TestedPlatform.removalUnavailable }
        if isWorking { return "Moving selected files to Trash…" }
        if isDiscovering { return "Wait for the file review to finish." }
        if discoveryFailure != nil { return "The file review failed. Close this review and try again." }
        if discovery == nil { return "Wait for the file review to finish." }
        if selectedIDs.isEmpty { return "Select at least one software bundle above." }
        if !hostClosed { return "Confirm above that your audio apps are closed and you have reviewed the files." }
        return nil
    }

    var body: some View {
        Group {
            if reviewOnly { cleanupSheet.task { beginReview() } }
            else { launchControl }
        }
        .onDisappear { discoveryTask?.cancel(); copyFeedbackTask?.cancel() }
        .alert("Cleanup result", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            if !keptFindings.isEmpty {
                Button("Copy kept locations") { copyKeptLocations() }.help("Copy the paths of files that will be preserved.")
            }
            Button("OK") { if reviewOnly { dismiss() } }
        } message: { Text(resultMessage ?? "") }
    }

    private var launchControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            if plan.items.isEmpty {
                Text(plan.items.isEmpty && !plan.excludedUserContentDescription.hasPrefix("Only the listed")
                     ? plan.excludedUserContentDescription
                     : "No files are eligible for in-app removal. Use the vendor’s uninstall instructions.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    "Experimental removal: review and select software bundles before moving them to Trash. Full removal may require the vendor’s uninstaller."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    discoveryTask?.cancel()
                    discoveryTask = nil
                    discovery = nil
                    discoveryFailure = nil
                    beginReview()
                    showsPreview = true
                } label: {
                    Label("Review Uninstall Files…", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(model.isScanning)
            }
        }
        .sheet(isPresented: $showsPreview) {
            cleanupSheet
        }
    }

    private var cleanupSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
            Text("Deep Uninstall Review")
                    .font(.title2.weight(.semibold))
                Text(reviewedPlan.displayName)
                    .foregroundStyle(.secondary)
            }

            if let criticalWarning { DoNotDeleteBanner(reason: criticalWarning) }
            Label(
                "Items are moved to Trash, so they remain recoverable until Trash is emptied.",
                systemImage: "arrow.uturn.backward.circle"
            )
            .foregroundStyle(.secondary)
            ForEach(preface, id: \.self) { line in
                Label(line, systemImage: "info.circle").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if isDiscovering { ProgressView("Searching associated files, including hidden entries…") }
            if let discoveryFailure { Text(discoveryFailure).foregroundStyle(.secondary) }
            if let manager = ManagerDefinition.matching(identifiers: identifiers) {
                Label("This product line may use \(manager.name). File removal won’t update a manager’s records; use its uninstaller when available.", systemImage: "exclamationmark.triangle")
                DisclosureGroup("Manager and official removal guidance") {
                    VendorManagerView(identifiers: identifiers)
                }
            }
            List {
                Section(selectedSizeSummary) {
                    if reviewedPlan.items.isEmpty {
                        Text("Nothing here can be removed safely: the identity or safety checks didn’t pass. Use the vendor’s instructions.")
                    }
                    ForEach(reviewedPlan.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(item.kind.rawValue, isOn: Binding(
                        get: { selectedIDs.contains(item.id) },
                        set: { if $0 { selectedIDs.insert(item.id) } else { selectedIDs.remove(item.id) } }
                    )).fontWeight(.medium).disabled(isWorking || isDiscovering)
                        .accessibilityLabel("Include " + item.path.lastPathComponent)
                    Text(item.path.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let bytes = bundleSizes[item.id] {
                        Text("File size: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let contents = bundleContents[item.id] {
                        DisclosureGroup("Bundle contents · \(contents.count) entries, including hidden files") {
                            ForEach(Array(contents.prefix(200)), id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                            if contents.count > 200 { Text("Showing the first 200 names. The complete bundle was inspected and will be rechecked before removal.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

                }
                if let discovery {
                    if !keptFindings.isEmpty {
                        Section("Settings and other files will be kept") {
                            Text("These files stay where they are and won’t be removed. Some may be shared with other software.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(showsKeptLocations ? "Hide locations" : "Show locations") { showsKeptLocations.toggle() }.help("Show or hide the related files that will be preserved.")
                                Button("Copy locations") { copyKeptLocations() }.help("Copy these file locations to the clipboard.")
                                if copiedLocations { Text("Locations copied").font(.caption).foregroundStyle(.secondary) }
                            }
                            if showsKeptLocations {
                                Text("Files remain in their original locations. No backup is created.")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(keptFindings) { finding in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(finding.path.lastPathComponent, systemImage: "lock.shield")
                                        Text((finding.path.path as NSString).abbreviatingWithTildeInPath).font(.caption).textSelection(.enabled)
                                        Text(finding.evidence).font(.caption).foregroundStyle(.secondary)
                                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.path]) }.help("Reveal this location in Finder. Nothing is removed.")
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        if !discovery.warnings.isEmpty {
                            Label("Some locations couldn’t be checked", systemImage: "exclamationmark.triangle")
                                .font(.subheadline.weight(.semibold))
                            Text("Additional related files may remain. Only the files you select will be moved to Trash.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Scan details") {
                            Text("\(discovery.inspectedEntries.formatted()) entries checked in system and user Applications and Library locations, including containers, logs, plugins, preferences, caches, support, saved state and launch-service folders, plus configured custom plugin folders. Hidden entries are included; links and package contents are skipped. Search depth is limited. This is not a whole-disk or complete ownership scan.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(discovery.warnings, id: \.self) { warning in
                                Text(warning.replacingOccurrences(of: NSHomeDirectory() + "/", with: "~/"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Label(
                reviewedPlan.excludedUserContentDescription,
                systemImage: "lock.shield"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !TestedPlatform.isTestedConfiguration {
                Text(TestedPlatform.removalCaution).font(.callout).fixedSize(horizontal: false, vertical: true)
            }

            Toggle(plan.items.contains { $0.kind == .driverBundle }
                   ? "I have closed my DAWs and audio apps and reviewed the selected files"
                   : "I have closed my DAWs and plugin hosts and reviewed the selected files", isOn: $hostClosed)
                .disabled(isWorking)
            if let removalDisabledReason {
                Text(removalDisabledReason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") {
                    discoveryTask?.cancel()
                    showsPreview = false
                    if reviewOnly { dismiss() }
                }
                .disabled(isWorking)
                Spacer()
                Text("\(selectedIDs.count) selected").font(.caption)
                HoldToTrashButton(enabled: removalDisabledReason == nil, title: removalDisabledReason == nil ? "Hold 5 seconds, then release to Trash" : (isWorking ? "Moving to Trash…" : "Complete the review above")) {
                    executeCleanup()
                }.help(removalDisabledReason ?? "Hold for five seconds, then release to move the selected software to Trash. Related files are preserved.").frame(width: 310, height: 32)
                    .id(selectedIDs.sorted().joined(separator: "|") + String(hostClosed))
            }
        }
        .padding(24)
        .frame(width: 780, height: 700)
        .interactiveDismissDisabled(isWorking)
        .onDisappear { discoveryTask?.cancel() }
    }

    /// Section title with the footprint of the current selection, once the preview has measured it.
    private var selectedSizeSummary: String {
        let selected = reviewedPlan.items.filter { selectedIDs.contains($0.id) }.compactMap { bundleSizes[$0.id] }
        guard !selected.isEmpty else { return "Eligible software bundles · select what to move to Trash" }
        return "Eligible software bundles · selected: \(ByteCountFormatter.string(fromByteCount: selected.reduce(0, +), countStyle: .file)) in files"
    }

    private func beginReview() {
        guard discoveryTask == nil else { return }
        previewPlan = plan
        selectedIDs = []
        hostClosed = false
        copiedLocations = false
        isDiscovering = true
        let ids = identifiers
        let roots = UninstallDiscovery.standardRoots + model.customPluginFolders.map { URL(fileURLWithPath: $0) }
        let original = plan
        discoveryTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                var contents: [String: [String]] = [:]
                var sizes: [String: Int64] = [:]
                var items: [CleanupItem] = []
                let report = try UninstallDiscovery.scan(identifiers: ids, roots: roots)
                let candidates = original.items + UninstallDiscovery.additionalSoftware(in: report, original: original)
                for item in candidates {
                    let snapshot = try BundleContentsPreview.scan(item.path)
                    guard CleanupSafety().validate(item) == nil else { throw CocoaError(.fileReadUnknown) }
                    contents[item.id] = snapshot.paths
                    sizes[item.id] = snapshot.totalBytes
                    items.append(CleanupItem(path: item.path, kind: item.kind,
                        containsUserCreatedContent: item.containsUserCreatedContent, contentsFingerprint: snapshot.fingerprint))
                }
                return (report, contents, CleanupPlan(displayName: original.displayName, items: items,
                    excludedUserContentDescription: original.excludedUserContentDescription), sizes)
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                discovery = result.0
                bundleContents = result.1
                previewPlan = result.2
                bundleSizes = result.3
            } catch is CancellationError { }
            catch { discoveryFailure = "The complete preview could not be built. Nothing can be removed from this review. " + error.localizedDescription }
            isDiscovering = false
        }
    }

    private func copyKeptLocations() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(keptLocationSummary, forType: .string)
        copiedLocations = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            copiedLocations = false
        }
    }

    private func executeCleanup() {
        guard TestedPlatform.removalAllowed else { resultMessage = TestedPlatform.removalUnavailable; return }
        guard discoveryFailure == nil, discovery != nil, hostClosed, !isWorking, !isDiscovering, !selectedIDs.isEmpty else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path })
        guard !reviewedPlan.items.contains(where: { selectedIDs.contains($0.id) && running.contains($0.path.resolvingSymlinksInPath().path) }) else {
            showsPreview = false
            resultMessage = "Quit the selected application before uninstalling it. Nothing was moved."
            return
        }
        isWorking = true
        let plan = CleanupPlan(displayName: reviewedPlan.displayName, items: reviewedPlan.items.filter { selectedIDs.contains($0.id) }, excludedUserContentDescription: reviewedPlan.excludedUserContentDescription)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let result = CleanupExecutor.execute(plan, safety: CleanupSafety(protectedPaths: running)) { path in
                    try TrashMover.moveToTrash(path)
                }
                return (result.movedCount, result.failures)
            }.value

            isWorking = false
            showsPreview = false
            if result.1.isEmpty {
                resultMessage = plan.items.contains { $0.kind == .driverBundle }
                    ? "The driver was moved to Trash. Any device it provided will disappear; log out and back in if audio apps misbehave. Keep Trash intact until you have checked your setup."
                    : "The selected software bundles were moved to Trash. Settings and external creative/support files were kept in their original locations. No backup was created. Keep Trash intact until you have checked your sessions."
                if !keptFindings.isEmpty {
                    resultMessage = (resultMessage ?? "") + "\n\n\(keptFindings.count) related locations identified and kept. Use Copy kept locations to save their paths."
                }
                if let onCompleted { onCompleted() } else { model.startScan() }
            } else {
                let movedSummary = result.0 > 0
                    ? "\(result.0) item\(result.0 == 1 ? "" : "s") moved to Trash. "
                    : ""
                resultMessage = movedSummary
                    + "Rescan and review a new plan before trying again:\n\n"
                    + result.1.joined(separator: "\n")
                if result.0 > 0 {
                    if let onCompleted { onCompleted() } else { model.startScan() }
                }
            }
        }
    }

}


/// The one red element in the app: reserved for items that must not be deleted.
struct DoNotDeleteBanner: View {
    let reason: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title3)
                .foregroundStyle(StudioUpkeepDesign.protection)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Don’t delete this")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(StudioUpkeepDesign.protection)
                Text(reason)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioUpkeepDesign.protection.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(StudioUpkeepDesign.protection.opacity(0.6)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: don’t delete this. \(reason)")
    }
}
