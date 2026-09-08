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
        let report = ScanReport(startedAt: Date(timeIntervalSince1970: 1), finishedAt: Date(timeIntervalSince1970: 2), records: [], locations: [])
        let result = StudioScanResult(report: report, products: [], daws: [], dawWarnings: [], dawScopeNotes: [])
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
