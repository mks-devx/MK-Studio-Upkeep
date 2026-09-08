// SPDX-License-Identifier: BUSL-1.1
import Foundation
import Combine
import ProducerUpToDateCore

@MainActor
final class AppUpdateModel: ObservableObject {
    let source = AppReleaseCheck.Source(Bundle.main.object(forInfoDictionaryKey: "StudioUpkeepReleaseRepository") as? String)
    @Published private(set) var busy = false
    @Published private(set) var message = "Check for a newer version of MK Studio Upkeep."
    @Published private(set) var releasePage: URL?
    @Published private(set) var checkedAt: Date?
    private var task: Task<Void, Never>?

    init() {
        if source == nil {
            message = "Private repository: check Releases in your browser while signed in to GitHub. The app does not access your GitHub account."
        }
    }

    func check(includeBetas: Bool) {
        guard !busy else { return }
        releasePage = nil
        checkedAt = nil
        guard let source else {
            releasePage = AppReleaseCheck.projectSource.releasesURL
            message = "Check the project’s private GitHub Releases page while signed in; automatic access to private releases is not configured."
            return
        }
        busy = true
        message = "Checking MK Studio Upkeep releases…"
        let installed = Bundle.main.object(forInfoDictionaryKey: "StudioUpkeepReleaseVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        task = Task {
            defer { busy = false; task = nil }
            do {
                let result = try await AppReleaseCheck.check(source: source, installed: installed, includeBetas: includeBetas)
                try Task.checkCancellation()
                checkedAt = Date()
                switch result {
                case let .update(version, page):
                    message = "MK Studio Upkeep \(version) is available. Review the release notes and macOS requirements before downloading."
                    releasePage = page
                case .current:
                    message = "You’re up to date with the published \(includeBetas ? "releases" : "stable releases")."
                case let .ahead(version):
                    message = "This build is newer than the latest published \(includeBetas ? "release" : "stable release") (\(version))."
                case .noReleases:
                    message = "No published \(includeBetas ? "releases" : "stable releases") with a Mac installer and checksum are available yet."
                }
            } catch {
                message = Task.isCancelled ? "Update check cancelled." : (error as? AppReleaseCheck.Failure)?.errorDescription ?? "Could not connect to GitHub. Check your connection and try again."
                if !Task.isCancelled { releasePage = source.releasesURL }
            }
        }
    }

    func cancel() { task?.cancel() }

    func resetResult() {
        guard !busy else { return }
        message = "Check for a newer version of MK Studio Upkeep."
        releasePage = nil
        checkedAt = nil
    }
}
