// SPDX-License-Identifier: BUSL-1.1
import AppKit
import Combine
import CryptoKit
import Foundation
import ProducerUpToDateCore

@MainActor
final class AppModel: ObservableObject {
    @Published var localReviewFilter: LocalReviewFilter = .all
    @Published private(set) var filterResetID = UUID()
    @Published private(set) var scanFailureMessage: String?
    private(set) var relatedEditions: [String: [NormalizedPluginProduct]] = [:]
    private let preferences: UserDefaults
    private let scanner: @Sendable (ScanConfiguration, Bool) async throws -> StudioScanResult

    enum ScanState {
        case ready
        case scanning(startedAt: Date, previous: ScanReport?)
        case complete(ScanReport)
        case failed(message: String)
    }

    @Published private(set) var scanState: ScanState = .ready
    @Published private(set) var dawWarnings: [String] = []
    @Published private(set) var dawScopeNotes: [String] = []
    @Published private(set) var installedDAWs: [InstalledDAWRecord] = []
    @Published private(set) var pluginUpdateResults: [PluginUpdateResult] = [] {
        didSet { pluginResultsByID = Dictionary(uniqueKeysWithValues: pluginUpdateResults.map { ($0.id, $0) }) }
    }
    private(set) var pluginResultsByID: [String: PluginUpdateResult] = [:]
    @Published private(set) var customPluginFolders: [String]

    func pluginResult(_ id: String) -> PluginUpdateResult? { pluginResultsByID[id] }
    var pluginCoverage: PluginUpdateCoverage { .init(results: pluginUpdateResults) }
    func resetLocalFilters() { filterResetID = UUID() }

    func addPluginFolder() {
        let panel = NSOpenPanel()
        panel.title = "Include an additional plugin folder"
        panel.message = "Select a folder containing AU, VST3, VST2 or CLAP bundles. Its subfolders will be scanned read-only. Rescan to apply changes."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        // Whole volumes and system or account roots are never plug-in folders; scanning them
        // would be slow, could prompt for folder access, and finds nothing the standard roots miss.
        let refused = ["/", "/System", "/Library", "/Users", "/Volumes", "/private", "/Applications", FileManager.default.homeDirectoryForCurrentUser.path]
        guard !refused.contains(path), !path.hasPrefix("/System/"), !path.hasPrefix("/private/") else {
            let alert = NSAlert()
            alert.messageText = "Choose a specific plug-in folder"
            alert.informativeText = "Whole volumes, system folders and your home folder are not plug-in folders. Pick the folder that directly contains the bundles."
            alert.runModal()
            return
        }
        if !customPluginFolders.contains(path) { customPluginFolders.append(path) }
        preferences.set(customPluginFolders, forKey: "customPluginFolders")
    }

    func removePluginFolder(_ path: String) {
        customPluginFolders.removeAll { $0 == path }
        preferences.set(customPluginFolders, forKey: "customPluginFolders")
    }
    @Published var pluginStatusFilter: InventorySection = .allPlugins
    @Published var intelOnlyFilter = false
    @Published var dawStatusFilter = "All DAWs"
    @Published var selectedSection: InventorySection = .allPlugins {
        didSet {
            localReviewFilter = .all
            switch selectedSection {
            case .updatesAvailable, .upToDate, .managedElsewhere, .notChecked:
                pluginStatusFilter = .allPlugins
                selectedSection = .allPlugins
            case .intelOnly:
                pluginStatusFilter = .allPlugins
                intelOnlyFilter = true
                selectedSection = .allPlugins
            default: break
            }
        }
    }
    @Published var selectedProductID: String?
    @Published var selectedDAWID: String?
    @Published var selectedUpdateID: String?
    @Published var searchText = ""
    @Published var showsHelp = false
    @Published var showsBugReport = false
    @Published var cleanupDAW: InstalledDAWRecord?
    @Published var cleanupProduct: NormalizedPluginProduct?
    @Published private(set) var catalogue: CatalogueSnapshot? = nil
    @Published private(set) var pluginReleases: [PluginReleaseRecord] = []
    @Published private(set) var dawReleases: [DAWReleaseRecord] = []
    private static let supportFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Studio Upkeep", isDirectory: true)
    let vendorCacheURL: URL
    /// Earlier builds cached whole vendor pages; the facts-only policy removes that file.
    private let legacyPageCacheURL: URL
    /// User identity confirmations stay on this Mac and never modify the catalogue.
    let identityConfirmationsURL: URL
    /// Names and versions from the previous scan, so the next one can say what changed. Local only.
    let scanSnapshotURL: URL
    @Published private(set) var lastScanChanges: ScanComparison?
    @Published var identityConfirmations = IdentityConfirmations()

    init(preferences: UserDefaults = .standard, storageDirectory: URL? = nil,
         scanner: @escaping @Sendable (ScanConfiguration, Bool) async throws -> StudioScanResult = {
             try await ScanPipeline.run(configuration: $0, scanDAWs: $1)
         }) {
        self.preferences = preferences
        self.scanner = scanner
        customPluginFolders = preferences.stringArray(forKey: "customPluginFolders") ?? []
        let directory = storageDirectory ?? Self.supportFolder
        vendorCacheURL = directory.appendingPathComponent("direct-vendor-facts.json")
        legacyPageCacheURL = directory.appendingPathComponent("direct-vendor-pages.json")
        identityConfirmationsURL = directory.appendingPathComponent("identity-confirmations.json")
        scanSnapshotURL = directory.appendingPathComponent("last-scan.json")
        if preferences.string(forKey: StudioUpkeepPreference.postScanDestination) == PostScanDestination.updates.rawValue {
            preferences.set(PostScanDestination.smart.rawValue, forKey: StudioUpkeepPreference.postScanDestination)
        }
        if preferences.string(forKey: StudioUpkeepPreference.accent) == "red" {
            preferences.set(AppAccent.monochrome.rawValue, forKey: StudioUpkeepPreference.accent)
        }
        if FileManager.default.fileExists(atPath: legacyPageCacheURL.path) {
            try? FileManager.default.removeItem(at: legacyPageCacheURL)
        }
        // Previous live-check caches are not loaded or applied.
        identityConfirmations = IdentityConfirmations.load(from: identityConfirmationsURL)
    }

    // Historical catalogue files and preferences are deliberately not read. Local scans
    // must never repopulate saved release comparisons, even after upgrading an older build.
    func refreshEvidence() {
        pluginUpdateResults = normalizedProducts.map { evaluate($0) }
        installedDAWs = installedDAWs.map { DAWUpdateEvaluator.evaluate($0, catalogue: []) }
    }

    var criticalUpdateCount: Int {
        guard let catalogue else { return 0 }
        let pluginCount = pluginUpdateResults.filter { result in
            guard result.updateState == .updateAvailable,
                  let release = pluginReleases.first(where: { PluginUpdateEvaluator.matches(result.product, release: $0) }),
                  let installed = result.installedVersion, let available = result.latestVersion else { return false }
            return ReleaseNotesQuery.releases(productID: release.catalogueID, installed: installed, available: available, notes: catalogue.releaseNotes).contains { $0.importance == .critical }
        }.count
        return pluginCount + installedDAWs.filter { daw in
            guard daw.updateState == .updateAvailable, let installed = daw.installedVersion,
                  let available = daw.latestVersion else { return false }
            return ReleaseNotesQuery.releases(productID: daw.definitionID, installed: installed, available: available, notes: catalogue.releaseNotes).contains { $0.importance == .critical }
        }.count
    }

    var menuBarStatus: String {
        if isScanning { return "Scanning…" }
        if scanFailureMessage != nil { return "Rescan failed · previous results shown" }
        if case .failed = scanState { return "Scan failed · open MK Studio Upkeep" }
        guard currentReport != nil else { return "Not scanned" }
        return "Local scan complete"
    }

    private var scanGeneration = UUID()
    private(set) var normalizedProducts: [NormalizedPluginProduct] = []
    private var scanTask: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = scanState {
            return true
        }
        return false
    }

    var currentReport: ScanReport? {
        switch scanState {
        case let .complete(report):
            return report
        case let .scanning(_, previous):
            return previous
        case .ready, .failed:
            return nil
        }
    }

    func startScan(configuration: ScanConfiguration? = nil) {
        scanTask?.cancel()
        scanFailureMessage = nil
        let generation = UUID()
        scanGeneration = generation
        let previousReport = currentReport
        let resolvedConfiguration = configuration
            ?? preferredScanConfiguration()
        let shouldScanDAWs = preferenceBool(
            StudioUpkeepPreference.scanDAWs,
            default: true
        )
        scanState = .scanning(startedAt: Date(), previous: previousReport)

        scanTask = Task {
            do {
                let result = try await scanner(resolvedConfiguration, shouldScanDAWs)
                guard !Task.isCancelled, scanGeneration == generation else { return }

                dawWarnings = result.dawWarnings
                dawScopeNotes = result.dawScopeNotes
                installedDAWs = result.daws.map {
                    DAWUpdateEvaluator.evaluate(
                        $0,
                        catalogue: dawReleases
                    )
                }
                normalizedProducts = result.products
                relatedEditions = LocalProductReview.relatedEditions(result.products)
                pluginUpdateResults = normalizedProducts.map { evaluate($0) }
                lastScanChanges = nil
                let scope = resolvedConfiguration.locations.map { $0.url.standardizedFileURL.path + "|" + $0.format.rawValue }.sorted().joined(separator: "\n")
                let scopeID = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
                if result.report.inaccessibleLocationCount == 0 && result.products.count <= ScanSnapshot.maximumEntries {
                    let snapshot = ScanSnapshot(finishedAt: result.report.finishedAt, products: result.products, scopeID: scopeID)
                    if let previous = ScanSnapshot.load(from: scanSnapshotURL), previous.canCompare(to: snapshot) {
                        lastScanChanges = ScanComparison(previous: previous, current: snapshot)
                    }
                    try? snapshot.save(to: scanSnapshotURL)
                }
                scanState = .complete(result.report)
                if selectedSection != .hardware && selectedSection != .drivers && selectedSection != .managers {
                    selectedSection = preferredSection(for: result.report)
                }
                selectedProductID = products(
                    in: selectedSection,
                    report: result.report
                ).first?.id
                selectedDAWID = installedDAWs.first?.id
                selectedUpdateID = visibleUpdates().first?.id
            } catch is CancellationError {
                guard scanGeneration == generation else { return }
                scanState = previousReport.map(ScanState.complete) ?? .ready
            } catch {
                guard scanGeneration == generation else { return }
                if let previousReport {
                    scanState = .complete(previousReport)
                    scanFailureMessage = "The rescan couldn’t finish. Results from the previous completed scan are still shown."
                } else {
                    scanState = .failed(
                        message: "The scan stopped before it could finish. \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func cancelScan() {
        scanGeneration = UUID()
        let previousReport = currentReport
        scanTask?.cancel()
        scanTask = nil
        scanState = previousReport.map(ScanState.complete) ?? .ready
    }

    private func preferredSection(for report: ScanReport) -> InventorySection {
        let destination = PostScanDestination(
            rawValue: preferences.string(
                forKey: StudioUpkeepPreference.postScanDestination
            ) ?? ""
        ) ?? .smart
        switch destination {
        case .updates:
            return .allPlugins
        case .attention:
            return .needsAttention
        case .plugins:
            return .allPlugins
        case .daws:
            return .allDAWs
        case .smart:
            break
        }

        let products = normalizedProducts
        if updateCount > 0 {
            return .updatesAvailable
        }
        if products.contains(where: { !$0.issues.isEmpty }) {
            return .needsAttention
        }
        return .allPlugins
    }

    private func preferredScanConfiguration() -> ScanConfiguration {
        let enabledFormats = Set(
            PluginFormat.allCases.filter { format in
                preferenceBool(
                    preferenceKey(for: format),
                    default: true
                )
            }
        )
        return ScanConfiguration.includingCustomFolders(
            customPluginFolders.map { URL(fileURLWithPath: $0, isDirectory: true) },
            enabledFormats: enabledFormats)
    }

    private func preferenceKey(for format: PluginFormat) -> String {
        switch format {
        case .audioUnit:
            return StudioUpkeepPreference.scanAudioUnits
        case .vst3:
            return StudioUpkeepPreference.scanVST3
        case .vst2:
            return StudioUpkeepPreference.scanVST2
        case .clap:
            return StudioUpkeepPreference.scanCLAP
        }
    }

    private func preferenceBool(
        _ key: String,
        default defaultValue: Bool
    ) -> Bool {
        guard preferences.object(forKey: key) != nil else {
            return defaultValue
        }
        return preferences.bool(forKey: key)
    }
}
