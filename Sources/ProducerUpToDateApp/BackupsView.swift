// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import ProducerUpToDateCore
import SwiftUI

struct RemovalBackupsListView: View {
    @EnvironmentObject private var model: AppModel
    let search: String
    @AppStorage(RemovalBackupPreferences.automaticDeletionKey) private var automaticDeletion = true

    private var operations: [RemovalBackupManifest] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.removalBackups }
        return model.removalBackups.filter { operation in
            operation.displayName.localizedCaseInsensitiveContains(query)
                || operation.items.contains { $0.originalPath.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Removal backups").font(.headline)
                    Text("Verified local copies created before in-app removal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await model.reloadRemovalBackups() } }
            }
            .padding(StudioUpkeepDesign.Space.regular)
            Divider()
            if let warning = model.removalBackupWarning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).padding(12)
            }
            if let failure = model.removalBackupFailure {
                BackupEmptyState(title: "Backup history is unavailable", detail: failure, symbol: "exclamationmark.triangle")
            } else if operations.isEmpty {
                BackupEmptyState(title: search.isEmpty ? "No removal backups" : "No matching backups",
                    detail: search.isEmpty
                        ? "A backup appears here after MK Studio Upkeep creates one before confirmed removal."
                        : "Try a product name or clear the search field.",
                    symbol: "externaldrive.badge.timemachine")
            } else {
                List(operations, selection: $model.selectedBackupID) { operation in
                    BackupTimelineRow(operation: operation, automaticDeletion: automaticDeletion)
                        .tag(operation.id)
                }
                .listStyle(.inset)
            }
        }
        .task { await model.reloadRemovalBackups() }
    }
}

struct RemovalBackupDetailView: View {
    @EnvironmentObject private var model: AppModel
    @State private var workingItem: UUID?
    @State private var resultMessage: String?
    @AppStorage(RemovalBackupPreferences.automaticDeletionKey) private var automaticDeletion = true

    private var operation: RemovalBackupManifest? {
        model.removalBackups.first { $0.id == model.selectedBackupID }
    }

    var body: some View {
        Group {
            if let operation {
                ScrollView {
                    VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.large) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(operation.displayName).font(.title2.weight(.semibold))
                            Text(operation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            Label(backupStatus(operation), systemImage: backupStatusSymbol(operation))
                                .font(.subheadline.weight(.medium))
                        }
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: operation.byteCount, countStyle: .file))
                            Text("·").foregroundStyle(.tertiary)
                            Text(automaticDeletion
                                 ? "Scheduled for deletion \(operation.expiresAt.formatted(date: .abbreviated, time: .omitted))"
                                 : "Automatic deletion is paused")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        ForEach(operation.items) { item in
                            BackupItemDetail(item: item, working: workingItem == item.id) {
                                restore(operation.id, item.id)
                            }
                            if item.id != operation.items.last?.id { Divider() }
                        }
                        Divider()
                        Button("Show backup in Finder") {
                            let url = model.removalBackupStore.root.appendingPathComponent(operation.id.uuidString)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .help("Reveal this local recovery copy. Do not edit its manifest or payload.")
                    }
                    .padding(StudioUpkeepDesign.Space.large)
                }
            } else {
                BackupEmptyState(title: "Select a backup", detail: "Choose an operation to review its files and restore options.", symbol: "clock.arrow.circlepath")
            }
        }
        .alert("Restore result", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") { }
        } message: { Text(resultMessage ?? "") }
    }

    private func restore(_ operationID: UUID, _ itemID: UUID) {
        guard workingItem == nil else { return }
        workingItem = itemID
        Task {
            resultMessage = await model.restoreBackup(operationID: operationID, itemID: itemID)
            workingItem = nil
        }
    }
}

struct RemovalBackupSettingsView: View {
    private enum PresentedAlert: Identifiable {
        case deleteExpired, deleteAll, result(String)
        var id: String {
            switch self {
            case .deleteExpired: "delete-expired"
            case .deleteAll: "delete-all"
            case .result: "result"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @AppStorage(RemovalBackupPreferences.enabledKey) private var enabled = true
    @AppStorage(RemovalBackupPreferences.automaticDeletionKey) private var automaticDeletion = true
    @AppStorage(RemovalBackupPreferences.retentionDaysKey) private var retentionDays = 30
    @State private var presentedAlert: PresentedAlert?
    @State private var workingItem: UUID?

    private var expired: [RemovalBackupManifest] { model.removalBackups.filter { $0.expiresAt <= Date() } }
    private var expiredBytes: Int64 { RemovalBackupSize.total(expired.map(\.byteCount)) }
    private var totalBytes: Int64 { RemovalBackupSize.total(model.removalBackups.map(\.byteCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.xLarge) {
            GroupBox("Protection") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Create a backup before removal", isOn: $enabled)
                    Text(enabled
                         ? "Every selected software bundle must be copied and verified before removal begins."
                         : "Backups are disabled. Recovery is limited to macOS Trash until it is emptied.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("Automatically delete old backups", isOn: $automaticDeletion)
                    HStack {
                        Text("Keep new backups for")
                        Spacer()
                        Picker("Keep new backups for", selection: $retentionDays) {
                            Text("7 days").tag(7)
                            Text("30 days").tag(30)
                            Text("90 days").tag(90)
                        }
                        .labelsHidden().frame(width: 120)
                    }
                    .disabled(!automaticDeletion)
                    Text("Existing backups keep the expiry date recorded when they were created. Turn off automatic deletion to keep them until you remove them manually.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Storage") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(model.removalBackups.count) backup operation\(model.removalBackups.count == 1 ? "" : "s")")
                        Spacer()
                        Text(backupSizeDescription(totalBytes)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Delete expired backups…") { presentedAlert = .deleteExpired }
                            .disabled(expired.isEmpty)
                        Button("Delete available backups…", role: .destructive) { presentedAlert = .deleteAll }
                            .disabled(model.removalBackups.isEmpty)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.open(model.removalBackupStore.root) }
                            .disabled(model.removalBackups.isEmpty)
                    }
                    if let warning = model.removalBackupWarning {
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                    }
                    if let failure = model.removalBackupFailure {
                        Label(failure, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Restore history").font(.headline)
                if model.removalBackups.isEmpty {
                    Text("No removal backups yet.").foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.removalBackups) { operation in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(operation.items) { item in
                                        BackupItemDetail(item: item, working: workingItem == item.id) {
                                            restore(operation.id, item.id)
                                        }
                                        if item.id != operation.items.last?.id { Divider() }
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                BackupTimelineRow(operation: operation, automaticDeletion: automaticDeletion)
                            }
                            Divider()
                        }
                    }
                }
            }
        }
        .task { await model.reloadRemovalBackups(applyRetention: true) }
        .onChange(of: automaticDeletion) { value in if value { Task { await model.reloadRemovalBackups(applyRetention: true) } } }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .deleteExpired:
                Alert(title: Text("Delete expired backups?"),
                    message: Text("This permanently deletes \(backupSizeDescription(expiredBytes)) of recovery data. Installed software is not affected."),
                    primaryButton: .destructive(Text("Delete \(expired.count) backup\(expired.count == 1 ? "" : "s")"), action: deleteExpired),
                    secondaryButton: .cancel())
            case .deleteAll:
                Alert(title: Text("Delete available backups?"),
                    message: Text("This permanently deletes \(model.removalBackups.count) backup operation\(model.removalBackups.count == 1 ? "" : "s") using \(backupSizeDescription(totalBytes)). This cannot be undone."),
                    primaryButton: .destructive(Text("Delete available"), action: deleteAll),
                    secondaryButton: .cancel())
            case let .result(message):
                Alert(title: Text("Backup result"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func restore(_ operationID: UUID, _ itemID: UUID) {
        workingItem = itemID
        Task {
            presentedAlert = .result(await model.restoreBackup(operationID: operationID, itemID: itemID))
            workingItem = nil
        }
    }

    private func deleteExpired() {
        Task {
            if let summary = await model.deleteExpiredRemovalBackups() {
                presentedAlert = .result("Deleted \(summary.operationCount) expired backup\(summary.operationCount == 1 ? "" : "s").")
            }
        }
    }

    private func deleteAll() {
        Task {
            if let summary = await model.deleteAllRemovalBackups() {
                presentedAlert = .result("Deleted \(summary.operationCount) backup operation\(summary.operationCount == 1 ? "" : "s").")
            }
        }
    }
}

private struct BackupTimelineRow: View {
    let operation: RemovalBackupManifest
    let automaticDeletion: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: backupStatusSymbol(operation)).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(operation.displayName).fontWeight(.medium).lineLimit(1)
                Text(operation.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: operation.byteCount, countStyle: .file)).font(.caption)
                Text(automaticDeletion ? "Until \(operation.expiresAt.formatted(date: .abbreviated, time: .omitted))" : "Kept")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BackupItemDetail: View {
    let item: RemovalBackupItem
    let working: Bool
    let restore: () -> Void
    private var destinationExists: Bool { FileManager.default.fileExists(atPath: item.originalPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(URL(fileURLWithPath: item.originalPath).lastPathComponent, systemImage: item.state == .restored ? "checkmark.circle" : "shippingbox")
                    .fontWeight(.medium)
                Spacer()
                Text(item.state == .restored ? "Restored" : item.state == .removed ? "Removed" : "Backed up")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text((item.originalPath as NSString).abbreviatingWithTildeInPath)
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(working ? "Restoring…" : destinationExists ? "Already installed" : "Restore") { restore() }
                    .disabled(working || destinationExists)
            }
        }
    }
}

private struct BackupEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private func backupStatus(_ operation: RemovalBackupManifest) -> String {
    if operation.restoredItemCount == operation.items.count { return "All items restored" }
    if operation.removedItemCount == 0 { return "Backup created; nothing removed" }
    if operation.removedItemCount < operation.items.count { return "Partial removal · \(operation.removedItemCount) of \(operation.items.count) items" }
    return "Ready to restore"
}

private func backupStatusSymbol(_ operation: RemovalBackupManifest) -> String {
    if operation.restoredItemCount == operation.items.count { return "checkmark.circle" }
    if operation.removedItemCount < operation.items.count { return "exclamationmark.triangle" }
    return "clock.arrow.circlepath"
}

private func backupSizeDescription(_ bytes: Int64) -> String {
    bytes == .max ? "Size unavailable" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
