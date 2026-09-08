// SPDX-License-Identifier: MPL-2.0
import AppKit
import ProducerUpToDateCore
import SwiftUI

@MainActor final class CacheBrowser: ObservableObject {
    @Published var report: CacheInspection.Report?
    @Published var busy = false
    @Published var failure: String?
    @Published var search = ""
    private var task: Task<Void, Never>?
    func inspect(daws: [InstalledDAWRecord]) {
        guard !busy else { return }
        busy = true; failure = nil
        let locations = CacheInspection.locations(daws: daws)
        task = Task {
            defer { busy = false; task = nil }
            let worker = Task.detached(priority: .utility) { try CacheInspection.inspect(locations) }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                report = result
            } catch is CancellationError { }
            catch { failure = "Cache inspection could not finish. Nothing was changed." }
        }
    }
    func cancel() { task?.cancel() }
    var visible: [CacheInspection.Entry] {
        (report?.entries ?? []).filter { search.isEmpty || $0.location.name.localizedCaseInsensitiveContains(search) || $0.location.path.lastPathComponent.localizedCaseInsensitiveContains(search) }
    }
}

struct CacheInspectionView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var browser: CacheBrowser
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Audio cache inspection").font(.title2.weight(.semibold))
                Text("See sizes in recognised locations. Nothing is deleted, and a large cache is not a health problem.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button(browser.busy ? "Inspecting…" : "Inspect cache sizes") { browser.inspect(daws: model.installedDAWs) }.help("Measure recognised cache locations without changing files.").disabled(browser.busy)
                    if browser.busy { Button("Cancel") { browser.cancel() }.help("Stop this operation or close this view.") }
                }
                DisclosureGroup("DAW coverage and precautions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bitwig Studio: plugin index inspection. Other caches, including the separate VST metadata file, are not measured.")
                        Text("Reason: plugin cache inspection at the location documented for Reason 12. Other versions may store files elsewhere.")
                        Text("FL Studio: standard cache folders only. For browser problems, use its own Reset browser cache control. Custom user-data locations are not inspected.")
                        Text("Maschine: standard cache folders only. Browser databases and favourites are preserved; they are not disposable caches.")
                        Text("Deleting caches manually can trigger rescans or remove useful data. Follow the vendor’s instructions for your version and a specific problem.")
                        Link("Bitwig documentation", destination: URL(string: "https://www.bitwig.com/support/technical_support/i-upgraded-my-vst-collection-now-something-is-strangemissing-why-30/")!)
                        Link("Reason documentation", destination: URL(string: "https://help.reasonstudios.com/hc/en-us/articles/11606128381458--Access-Denied-when-launching-Reason-12-on-Mac")!)
                        Link("FL Studio documentation", destination: URL(string: "https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/envsettings_files.htm")!)
                        Link("Maschine documentation", destination: URL(string: "https://support.native-instruments.com/support/solutions/articles/69000879672-my-komplete-kontrol-maschine-browser-has-duplicate-presets")!)
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                if let failure = browser.failure { Text(failure).foregroundStyle(.secondary) }
                if let report = browser.report {
                    Text("Checked \(report.checkedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    if report.skipped > 0 {
                        Text("Some locations could not be measured. Links, inaccessible folders and locations beyond the search limit are skipped.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if browser.visible.isEmpty {
                        Text(report.entries.isEmpty ? "No supported cache folders were found. This does not mean your Mac has no audio caches." : "No cache locations match your search.")
                    }
                    ForEach(browser.visible) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.location.name).font(.headline)
                            Text((entry.measurement.incomplete ? "At least " : "") + ByteCountFormatter.string(fromByteCount: entry.measurement.bytes, countStyle: .file))
                                .font(.title3).monospacedDigit()
                            Text((entry.location.path.path as NSString).abbreviatingWithTildeInPath).font(.caption).textSelection(.enabled)
                            Text(entry.location.evidence).font(.caption).foregroundStyle(.secondary)
                            if entry.measurement.incomplete { Text("Measurement incomplete.").font(.caption).foregroundStyle(.secondary) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.location.path]) }.help("Reveal this location in Finder. Nothing is removed.")
                        }
                        Divider()
                    }
                }
                Text("Logical file sizes, not reclaimable disk space. Files may change while audio apps are running. No file contents are read.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.onDisappear { browser.cancel() }
    }
}

struct CacheInspectionContextView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspection only").font(.headline)
                Text("This view offers no cache deletion. Cache size never contributes to Needs Attention.")
                Text("Coverage: the shared AudioUnitCache folder and standard user/system cache folders whose names exactly match recognised installed DAW identifiers. Documented plugin-index and cache folders are also checked for detected Bitwig Studio and Reason installations. Other vendor-specific and container locations may not be covered.")
                Text("Projects, recordings, recovery folders, presets, sample libraries and licence locations are not search roots. Files inside a supported cache folder are counted by size only; they are not classified as safe to remove.")
                Text("Resetting an Audio Unit cache can require a plugin rescan. Use your DAW or vendor’s instructions for a specific problem, not routine cleaning.")
                Link("Vendor documentation · Audio Unit cache", destination: URL(string: "https://support.arturia.com/hc/en-us/articles/4405741289618-Plug-ins-not-detected-with-Logic-Pro-Mainstage-or-Garage-Band-What-should-i-do")!)
            }.font(.subheadline).foregroundStyle(.secondary).padding(24)
        }
    }
}
