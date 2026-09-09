// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import ProducerUpToDateCore

@MainActor
extension AppModel {
    func reloadRemovalBackups(applyRetention: Bool = false) async {
        do {
            if applyRetention && removalBackupPreferences.automaticallyDeletesExpired {
                _ = try await removalBackupStore.deleteExpired()
            }
            removalBackups = try await removalBackupStore.list()
            if !removalBackups.contains(where: { $0.id == selectedBackupID }) {
                selectedBackupID = removalBackups.first?.id
            }
            removalBackupFailure = nil
        } catch {
            removalBackupFailure = error.localizedDescription
        }
    }

    func restoreBackup(operationID: UUID, itemID: UUID) async -> String {
        do {
            let root = removalBackupStore.root
            let destination = try await removalBackupStore.restore(operationID: operationID, itemID: itemID,
                safety: CleanupSafety()) { source, destination in
                    try TrashMover.restoreFromBackup(source, to: destination, backupRoot: root)
                }
            await reloadRemovalBackups()
            return "Restored \(destination.lastPathComponent) to its original location. Rescan before opening a DAW."
        } catch {
            await reloadRemovalBackups()
            return error.localizedDescription
        }
    }

    func deleteExpiredRemovalBackups() async -> RemovalBackupDeletionSummary? {
        do {
            let summary = try await removalBackupStore.deleteExpired()
            await reloadRemovalBackups()
            return summary
        } catch {
            removalBackupFailure = error.localizedDescription
            return nil
        }
    }

    func deleteAllRemovalBackups() async -> RemovalBackupDeletionSummary? {
        do {
            let summary = try await removalBackupStore.deleteAll()
            await reloadRemovalBackups()
            return summary
        } catch {
            removalBackupFailure = error.localizedDescription
            return nil
        }
    }
}
