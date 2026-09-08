// SPDX-License-Identifier: BUSL-1.1
// Headless app-state regressions. Only synthetic records and temporary preferences are used.
import Foundation
import Darwin
@testable import ProducerUpToDateCore

@main struct AppStateCheck {
    @MainActor static func main() async throws {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }
        let unknownMIDI = MIDIHardwareRecord(id: 4_000_000_000, name: "Fixture MIDI", manufacturer: "Fixture", offline: nil)
        let item = HardwareBrowser.Item(id: "fixture", name: unknownMIDI.name, subtitle: "Fixture", group: .midi, midi: unknownMIDI)
        check(item.routeLine.hasPrefix("Availability unknown"), "Unknown MIDI availability must not become Connected")
        let hardware = HardwareBrowser()
        hardware.report = HardwareScanReport(devices: [], drivers: [], midiDevices: [unknownMIDI], warnings: [])
        check(hardware.availableMIDICount == 0, "Unknown MIDI availability must not count as available")
        for (offline, label) in [(true, "Saved entry, not available"), (false, "Available to MIDI apps")] {
            let device = MIDIHardwareRecord(id: 4_000_000_001, name: "Fixture MIDI", manufacturer: "Fixture", offline: offline)
            let row = HardwareBrowser.Item(id: "fixture", name: device.name, subtitle: "Fixture", group: .midi, midi: device)
            check(row.routeLine.hasPrefix(label), "MIDI availability must preserve the reported state")
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("app-state-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let preferences = UserDefaults(suiteName: "app-state-" + UUID().uuidString)!
        preferences.setVolatileDomain(["scanDAWs": false], forName: UserDefaults.argumentDomain)
        let fixtureHome = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-home")
        let fixtureVolume = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-volume")
        check(!AppModel.isEligiblePluginFolder(fixtureVolume, home: fixtureHome, volumeRoot: fixtureVolume),
              "A mounted volume root must not be accepted as a custom plugin folder")
        check(!AppModel.isEligiblePluginFolder(fixtureVolume.appendingPathComponent("Plugins/.."), home: fixtureHome, volumeRoot: fixtureVolume),
              "Standardised volume-root paths must also be rejected")
        check(AppModel.isEligiblePluginFolder(fixtureVolume.appendingPathComponent("Plugins"), home: fixtureHome, volumeRoot: fixtureVolume),
              "A specific plugin subfolder on a mounted volume must remain eligible")
        for path in ["/", "/System", "/System/Library", "/Library", "/Users", "/Volumes", "/private", "/private/FixturePlugins", "/Applications", fixtureHome.path] {
            check(!AppModel.isEligiblePluginFolder(URL(fileURLWithPath: path), home: fixtureHome, volumeRoot: URL(fileURLWithPath: "/")),
                  "Existing system and account root exclusions must remain enforced")
        }
        check(AppModel.isEligiblePluginFolder(fixtureHome.appendingPathComponent("Audio Plugins"), home: fixtureHome, volumeRoot: URL(fileURLWithPath: "/")),
              "A specific user plugin folder must remain eligible")
        let report = ScanReport(startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), records: [], locations: [])
        let result = StudioScanResult(report: report, products: [], daws: [], dawWarnings: [], dawScopeNotes: [])
        let legacyPreferences = UserDefaults(suiteName: "app-state-legacy-" + UUID().uuidString)!
        legacyPreferences.setVolatileDomain(["customPluginFolders": ["/"], "scanDAWs": false], forName: UserDefaults.argumentDomain)
        let legacySource = FixtureInventorySource(products: [], daws: [])
        let legacyModel = AppModel(preferences: legacyPreferences, storageDirectory: folder.appendingPathComponent("legacy"),
            scanner: { _, _ in await legacySource.scan() })
        legacyModel.startScan()
        try await finishScan(legacyModel)
        check(await legacySource.scanCount == 0, "A saved whole-volume root must be rejected before invoking the scanner")
        if case let .failed(message) = legacyModel.scanState {
            check(message.contains("Settings") && message.contains("Scanning"), "A rejected saved folder must explain where to correct it")
        } else { check(false, "An invalid saved folder must show a scan failure before the first result") }
        legacyModel.startScan(configuration: .init(locations: []))
        try await finishScan(legacyModel)
        let previousLegacyReport = legacyModel.currentReport
        let previousScanCalls = await legacySource.scanCount
        legacyModel.startScan()
        try await finishScan(legacyModel)
        check(await legacySource.scanCount == previousScanCalls, "Invalid saved roots must not reach the scanner during a rescan")
        check(legacyModel.currentReport == previousLegacyReport && legacyModel.scanFailureMessage?.contains("Settings") == true,
              "Rejecting an invalid saved folder must preserve prior results and disclose the configuration problem")
        check(legacyModel.customPluginFolders == ["/"] && legacyPreferences.stringArray(forKey: "customPluginFolders") == ["/"],
              "Rejecting a saved root must preserve it for review in Settings")
        let sequence = FixtureScanSequence(result: result)
        let model = AppModel(preferences: preferences, storageDirectory: folder, scanner: { _, _ in try await sequence.scan() })

        check(LocalReviewFilter.navigationCases.allSatisfy {
            [.cannotRun, .differentVersions, .repeatedCopies, .relatedEditions].contains($0)
        }, "Review navigation must offer only installed-file findings, never external edition suggestions")
        check(Set(LocalReviewFilter.navigationCases) == Set(LocalReviewFilter.allCases).subtracting([.all]), "Every finding must be available in both navigation layouts")
        check(ReviewEmptyMessage.make(for: .all, hasUserFilters: false) == nil, "The ordinary inventory must retain its own empty state")
        for destination in LocalReviewFilter.navigationCases {
            let empty = ReviewEmptyMessage.make(for: destination, hasUserFilters: false)
            check(empty != nil && empty?.title.contains("filters") == false, "An empty review with no extra filters must explain that no findings were identified")
            check(ReviewEmptyMessage.make(for: destination, hasUserFilters: true) == nil, "Search, category or architecture narrowing must retain the filter-reset state")
            model.searchText = "previous search"
            model.intelOnlyFilter = true
            let previousReset = model.filterResetID
            model.navigate(to: destination)
            check(model.selectedSection == .allPlugins && model.localReviewFilter == destination, "Review navigation must select its finding")
            check(model.searchText.isEmpty && !model.intelOnlyFilter && model.filterResetID != previousReset, "Review navigation must clear unrelated filters")
        }
        model.searchText = "Fixture version 1"
        model.dawStatusFilter = "Not verified"
        model.showDAW("fixture-daw-2")
        check(model.selectedSection == .allDAWs && model.selectedDAWID == "fixture-daw-2" && model.searchText.isEmpty && model.dawStatusFilter == "All DAWs", "Following another DAW installation must reveal its row")
        model.searchText = "previous product"
        model.navigate(to: LocalReviewFilter.relatedEditions)
        let beforeProductLink = model.filterResetID
        model.showProduct("fixture-product-2")
        check(model.localReviewFilter == .all && model.selectedProductID == "fixture-product-2" && model.filterResetID != beforeProductLink, "Product links must reset category and review filters even in the same section")

        model.startScan(configuration: .init(locations: []))
        try await finishScan(model)
        check(model.currentReport == report && model.scanFailureMessage == nil, "Initial synthetic scan must finish")
        model.startScan(configuration: .init(locations: []))
        try await finishScan(model)
        check(model.currentReport == report && model.scanFailureMessage != nil && model.menuBarStatus.contains("previous results"), "Failed rescan must retain results and disclose failure")
        model.startScan(configuration: .init(locations: []))
        try await finishScan(model)
        check(model.scanFailureMessage == nil && model.currentReport == report, "A successful retry must clear the old failure")

        // A repeated scan must not replace a visible selection with a hidden first row.
        let alpha = fixtureProduct("Alpha", architectures: [.arm64, .x86_64])
        let beta = fixtureProduct("Beta", architectures: [.x86_64])
        let dawAlpha = fixtureDAW("Alpha")
        let dawBeta = fixtureDAW("Beta")
        let inventory = FixtureInventorySource(products: [alpha, beta], daws: [dawAlpha, dawBeta])
        preferences.set(PostScanDestination.daws.rawValue, forKey: StudioUpkeepPreference.postScanDestination)
        let filteredModel = AppModel(preferences: preferences, storageDirectory: folder.appendingPathComponent("selection"),
            scanner: { _, _ in await inventory.scan() })
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.selectedSection == .allDAWs, "The first scan must honour the configured destination")
        filteredModel.searchText = "Beta"
        filteredModel.selectedDAWID = dawBeta.id
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.selectedDAWID == dawBeta.id, "An unchanged DAW rescan must retain the selected search match")

        filteredModel.navigate(to: .allPlugins)
        filteredModel.searchText = "Beta"
        filteredModel.intelOnlyFilter = true
        filteredModel.selectedProductID = beta.id
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.selectedSection == .allPlugins && filteredModel.searchText == "Beta" && filteredModel.intelOnlyFilter,
              "A rescan must preserve the current section and filters instead of applying the first-scan destination")
        check(filteredModel.selectedProductID == beta.id, "An unchanged plugin rescan must retain the selected search and architecture match")

        filteredModel.searchText = ""
        filteredModel.intelOnlyFilter = false
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.selectedProductID == beta.id, "A rescan must preserve a valid selection even when other rows are visible")
        filteredModel.navigate(to: LocalReviewFilter.relatedEditions)
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.localReviewFilter == .relatedEditions, "A rescan must retain the active local review")

        filteredModel.navigate(to: .allPlugins)
        filteredModel.searchText = "Beta"
        filteredModel.selectedProductID = beta.id
        await inventory.replace(products: [alpha], daws: [dawAlpha])
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.selectedProductID == nil, "A removed search match must clear selection, never reveal an unrelated product")
        filteredModel.navigate(to: .allDAWs)
        filteredModel.searchText = "Beta"
        filteredModel.selectedDAWID = dawBeta.id
        filteredModel.startScan(configuration: .init(locations: []))
        try await finishScan(filteredModel)
        check(filteredModel.selectedDAWID == nil, "A missing DAW search match must clear selection")

        let audioGate = AudioReadGate()
        let status = MacStatusModel(audioReader: { await audioGate.read() })
        status.refreshAudio()
        check(await audioGate.waitForRequests(1), "The first synthetic audio read must start")
        status.reset()
        status.refreshAudio()
        let replacementStarted = await audioGate.waitForRequests(2)
        check(replacementStarted, "Reset followed by refresh must start a replacement audio read immediately")
        await audioGate.finish(0, name: "Previous output")
        // Give the resumed model task a main-actor turn before inspecting its deferred cleanup.
        try await Task.sleep(for: .milliseconds(20))
        check(status.audioBusy && status.audioOutput == nil,
              "An old cancelled audio read must not publish or clear a replacement's busy state")
        if replacementStarted {
            await audioGate.finish(1, name: "Current output")
            let audioDeadline = Date().addingTimeInterval(2)
            while status.audioBusy && Date() < audioDeadline { try await Task.sleep(for: .milliseconds(5)) }
            check(!status.audioBusy && status.audioOutput?.name == "Current output",
                  "The replacement audio read must publish and finish normally")
        }

        let reading = LatestDetailReading<String>()
        let oldGate = ReadGate()
        let old = Task { await reading.read { await oldGate.read() } }
        await oldGate.waitForStart()
        check(reading.value == nil, "A new detail read must clear previous content")
        await reading.read { "current selection" }
        await oldGate.finish("previous selection")
        await old.value
        check(reading.value == "current selection", "A late read from a previous selection must not overwrite current details")
        let cancelledGate = ReadGate()
        let cancelled = Task { await reading.read { await cancelledGate.read() } }
        await cancelledGate.waitForStart()
        check(reading.value == nil, "Starting another read must show loading, not the previous result")
        cancelled.cancel()
        await cancelledGate.finish("cancelled result")
        await cancelled.value
        check(reading.value == nil, "Cancelled detail reads must never publish")
        if !failures.isEmpty {
            for failure in failures { print("FAIL: " + failure) }
            exit(1)
        }
        print("PASS: app-state regression checks")
    }

    @MainActor private static func finishScan(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.isScanning && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        guard !model.isScanning else { throw NSError(domain: "ScanTimeout", code: 1) }
    }

    private static func fixtureProduct(_ name: String, architectures: [BinaryArchitecture]) -> NormalizedPluginProduct {
        let bundle = PluginBundleRecord(id: name, name: name, vendor: "Example", format: .vst3,
            bundleIdentifier: "com.example." + name.lowercased(), displayVersion: "1.0", buildVersion: nil,
            path: URL(fileURLWithPath: "/tmp/" + name + ".vst3"), executablePath: nil,
            architectures: architectures, fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        return NormalizedPluginProduct(id: name, name: name, vendor: "Example", bundles: [bundle],
            confidence: .high, matchEvidence: [], requiresVerification: false)
    }

    private static func fixtureDAW(_ name: String) -> InstalledDAWRecord {
        InstalledDAWRecord(id: name, definitionID: "fixture-" + name.lowercased(), name: name,
            vendor: "Example", bundleIdentifier: "com.example.daw." + name.lowercased(), displayVersion: "1.0",
            buildVersion: nil, path: URL(fileURLWithPath: "/tmp/" + name + ".app"), executablePath: nil,
            architectures: [.arm64, .x86_64])
    }
}

private actor FixtureInventorySource {
    var products: [NormalizedPluginProduct]
    var daws: [InstalledDAWRecord]
    private(set) var scanCount = 0
    init(products: [NormalizedPluginProduct], daws: [InstalledDAWRecord]) {
        self.products = products; self.daws = daws
    }
    func replace(products: [NormalizedPluginProduct], daws: [InstalledDAWRecord]) {
        self.products = products; self.daws = daws
    }
    func scan() -> StudioScanResult {
        scanCount += 1
        let report = ScanReport(startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2),
            records: products.flatMap(\.bundles), locations: [])
        return StudioScanResult(report: report, products: products, daws: daws, dawWarnings: [], dawScopeNotes: [])
    }
}

private actor AudioReadGate {
    private var continuations: [CheckedContinuation<AudioOutputSnapshot?, Never>?] = []
    func read() async -> AudioOutputSnapshot? {
        await withCheckedContinuation { continuations.append($0) }
    }
    func waitForRequests(_ count: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(1)
        while continuations.count < count && Date() < deadline { await Task.yield() }
        return continuations.count >= count
    }
    func finish(_ index: Int, name: String) {
        guard continuations.indices.contains(index) else { return }
        continuations[index]?.resume(returning: AudioOutputSnapshot(name: name, sampleRate: 48_000, bufferFrames: 128, bitDepths: [24]))
        continuations[index] = nil
    }
}

private actor FixtureScanSequence {
    let result: StudioScanResult
    private var attempts = 0
    init(result: StudioScanResult) { self.result = result }
    func scan() throws -> StudioScanResult {
        attempts += 1
        if attempts == 2 { throw NSError(domain: "SyntheticScanFailure", code: 1) }
        return result
    }
}

private actor ReadGate {
    private var continuation: CheckedContinuation<String, Never>?
    func read() async -> String { await withCheckedContinuation { continuation = $0 } }
    func waitForStart() async { while continuation == nil { await Task.yield() } }
    func finish(_ result: String) { continuation?.resume(returning: result); continuation = nil }
}
