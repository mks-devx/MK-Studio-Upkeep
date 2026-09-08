// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

@MainActor final class MacStatusModel: ObservableObject {
    @Published var audioOutput: AudioOutputSnapshot?
    @Published var audioDate: Date?
    @Published var audioBusy = false
    private var audioTask: Task<Void, Never>?
    @Published var memory: MemorySnapshot?
    @Published var memoryDate: Date?
    @Published var available: Int64?
    @Published var capacity: Int64?
    @Published var bootDate: Date?
    @Published var thermal = "Not checked"
    @Published var lowPower = false
    @Published var plugins: StorageMeasurement.Result?
    @Published var daws: StorageMeasurement.Result?
    @Published var busy = false
    @Published var failure: String?
    @Published var activity: [ProcessActivity.Entry] = []
    @Published var memoryActivity: [ProcessActivity.Entry] = []
    @Published var activityDate: Date?
    @Published var activityBusy = false
    @Published var activityFailure: String?
    private var activityTask: Task<Void, Never>?
    private var task: Task<Void, Never>?

    func refresh() {
        refreshAudio()
        refreshMemory()
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        available = values?.volumeAvailableCapacity.map(Int64.init)
        capacity = values?.volumeTotalCapacity.map(Int64.init)
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        bootDate = sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 ? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec)) : nil
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "High thermal pressure"
        case .critical: thermal = "Critical thermal pressure"
        @unknown default: thermal = "Unknown"
        }
    }
    func refreshAudio() {
        guard !audioBusy else { return }
        audioBusy = true
        audioOutput = nil
        audioTask = Task {
            defer { audioBusy = false; audioTask = nil }
            let worker = Task.detached(priority: .utility) { AudioOutputSnapshot.read() }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            audioOutput = result
            audioDate = Date()
        }
    }
    func refreshMemory() { memory = MemorySnapshot.read(); memoryDate = Date() }
    func measure(plugins: [URL], daws: [URL]) {
        guard !busy else { return }
        busy = true; failure = nil
        task = Task {
            defer { busy = false; task = nil }
            let worker = Task.detached(priority: .utility) {
                (try StorageMeasurement.measure(plugins), try StorageMeasurement.measure(daws))
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                self.plugins = result.0; self.daws = result.1
            } catch is CancellationError { }
            catch { failure = "Storage measurement could not finish." }
        }
    }
    func checkActivity() {
        guard !activityBusy else { return }
        refreshMemory()
        activityBusy = true; activityFailure = nil
        activityTask = Task {
            defer { activityBusy = false; activityTask = nil }
            let worker = Task.detached(priority: .utility) { try ProcessActivity.read() }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                activity = result.cpu; memoryActivity = result.memory; activityDate = Date()
            } catch is CancellationError { }
            catch { activityFailure = "Process activity could not be read. Try Activity Monitor." }
        }
    }
    func cancel() { task?.cancel(); activityTask?.cancel(); audioTask?.cancel() }
    func reset() { cancel(); plugins = nil; daws = nil }
}

struct MacStatusView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var status: MacStatusModel
    let report: ScanReport
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This Mac").font(.headline)
                Spacer()
                Button("Refresh") { status.refresh() }.help("Refresh this Mac’s status.").controlSize(.small)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: StudioUpkeepDesign.Space.regular) {
                systemReading("macOS", symbol: "desktopcomputer", value: Text(macOSVersion))
                if let boot = status.bootDate {
                    systemReading("Last restarted", symbol: "clock.arrow.circlepath", value: Text(boot, style: .relative))
                        .help(boot.formatted(date: .abbreviated, time: .shortened))
                }
                systemReading("Thermal state", symbol: "thermometer.medium", value: Text(status.thermal))
                systemReading("Low Power Mode", symbol: "battery.75percent", value: Text(status.lowPower ? "On" : "Off"))
            }
            Divider()
            audioReadings
            Divider()
            storageVisual
            HStack(alignment: .top, spacing: StudioUpkeepDesign.Space.large) {
                softwareReading("Plugin files", symbol: "puzzlepiece.extension", value: sizeLabel(status.plugins))
                softwareReading("DAW applications", symbol: "waveform", value: sizeLabel(status.daws))
            }
            HStack {
                Button(status.busy ? "Measuring…" : "Measure software size") {
                    status.measure(plugins: report.records.map(\.path), daws: model.installedDAWs.map(\.path))
                }.help("Measure installed software bundles without changing them.").disabled(status.busy)
                if status.busy { Button("Cancel") { status.cancel() }.help("Stop this operation or close this view.") }
            }
            if let failure = status.failure { Text(failure).foregroundStyle(.secondary) }
            Text("Software size covers scanned bundles across their volumes. External libraries and samples are excluded; this is not reclaimable space.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            memoryReadings
            Divider()
            activityReadings
            HStack {
                Button("Activity Monitor") { openSystemTool("com.apple.ActivityMonitor") }.help("Open macOS Activity Monitor to inspect running processes.")
                Button("Audio MIDI Setup") { openSystemTool("com.apple.audio.AudioMIDISetup") }.help("Open macOS audio and MIDI device settings.")
            }
            Text("System readings are a snapshot, not a guarantee of audio stability. Check your DAW for its buffer setting; MIDI clock quality requires an active timing test.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .onAppear { status.refresh() }
        .onDisappear { status.cancel() }
        .onChange(of: report.finishedAt) { _ in status.reset(); status.refresh() }
    }
    private var audioReadings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audio output").font(.headline)
                Spacer()
                Button(status.audioBusy ? "Reading…" : "Refresh audio") { status.refreshAudio() }
                    .disabled(status.audioBusy).controlSize(.small)
                    .help("Read the macOS output device and its current settings without changing them.")
            }
            if let output = status.audioOutput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS output device").font(.caption).foregroundStyle(.secondary)
                    Text(output.name).font(.title3.weight(.medium))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 12) {
                    systemReading("Sample rate", symbol: "waveform", value: Text(output.sampleRate.map {
                        ($0 / 1000).formatted(.number.precision(.fractionLength(0...3))) + " kHz"
                    } ?? "Unavailable"))
                    systemReading("Device buffer", symbol: "square.stack", value: Text(output.bufferFrames.map {
                        $0.formatted() + " frames"
                    } ?? "Unavailable"))
                    systemReading("Device bit depth", symbol: "slider.horizontal.3", value: Text(output.bitDepths.map {
                        $0.map { "\($0)-bit" }.joined(separator: " / ")
                    } ?? "Unavailable"))
                }
            } else {
                Text(status.audioBusy ? "Reading audio settings…" : "The macOS output device could not be read. Check Audio MIDI Setup, then refresh.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Your DAW may use a different device or buffer. Device bit depth describes the output stream, not your recording settings.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let date = status.audioDate, !status.audioBusy {
                Text("Checked \(date.formatted(date: .omitted, time: .shortened)) · refresh after changing audio settings")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var memoryReadings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memory").font(.headline)
                Spacer()
                Button("Refresh memory") { status.refreshMemory() }.help("Read a new memory snapshot; no programs are closed.").controlSize(.small)
            }
            if let memory = status.memory {
                Text("\(memory.used.map { formatMemory(Int64(clamping: $0)) } ?? "Unavailable") used · \(formatMemory(Int64(clamping: memory.total))) RAM")
                    .font(.title3.weight(.medium)).monospacedDigit()
                if let used = memory.used, memory.total > 0 {
                    ProgressView(value: Double(used), total: Double(memory.total))
                        .accessibilityLabel("Estimated RAM usage")
                }
                HStack(spacing: 24) {
                    Text("Pressure: \(memory.pressure)")
                    Text("Compressed: \(memory.compressed.map { formatMemory(Int64(clamping: $0)) } ?? "Unavailable")")
                    Text("Swap used: \(memory.swap.map { formatMemory(Int64(clamping: $0)) } ?? "Unavailable")")
                }.font(.caption).foregroundStyle(.secondary)
            }
            if let date = status.memoryDate {
                Text("Checked \(date.formatted(date: .omitted, time: .shortened)) · refresh for a new snapshot")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("RAM usage is estimated and may differ from Activity Monitor. Memory pressure is more useful than a full RAM bar; compression and swap alone do not prove audio problems. Nothing is cleared or changed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activityReadings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Process activity").font(.headline)
                Spacer()
                Button(status.activityBusy ? "Checking…" : "Check activity") { status.checkActivity() }.help("Read CPU and memory use; no programs are closed.")
                    .disabled(status.activityBusy).controlSize(.small)
            }
            if let date = status.activityDate {
                Text("Highest recent CPU use · checked \(date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(status.activity) { entry in
                    HStack {
                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                        Text("PID \(entry.id)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(entry.cpu, specifier: "%.1f")% CPU").monospacedDigit()
                    }.accessibilityElement(children: .combine)
                }
                Divider()
                Text("Highest memory use").font(.subheadline.weight(.semibold))
                ForEach(status.memoryActivity) { entry in
                    HStack {
                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                        Text("PID \(entry.id)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatMemory(Int64(clamping: entry.residentBytes))).monospacedDigit()
                    }.accessibilityElement(children: .combine)
                }
                Text("Resident RAM per process, including shared pages. These values are not the same as Activity Monitor’s Memory column and cannot be added to get total RAM usage. Helper processes are listed separately.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Check which processes are using the most CPU and resident RAM on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let failure = status.activityFailure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            Text("A recent average, not live monitoring. CPU use can exceed 100%. High use alone does not prove audio dropouts; check your DAW’s audio meter while playing. Process names stay on this Mac.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func systemReading(_ title: String, symbol: String, value: Text) -> some View {
        HStack(alignment: .top, spacing: StudioUpkeepDesign.Space.small) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(.secondary)
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                value.font(.subheadline.weight(.medium)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, StudioUpkeepDesign.Space.small)
    }

    private var storageVisual: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
            Text("Home volume").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: StudioUpkeepDesign.Space.small) {
                Text(status.available.map(format) ?? "Unavailable")
                    .font(.largeTitle.weight(.semibold)).monospacedDigit()
                if status.available != nil { Text("free").foregroundStyle(.secondary) }
            }
            if let capacity = status.capacity, capacity > 0,
               let available = status.available, available >= 0, available <= capacity {
                let used = capacity - available
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(BrandColor.accent)
                            .frame(width: geometry.size.width * CGFloat(Double(used) / Double(capacity)))
                    }
                }
                .frame(height: 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Home volume storage")
                .accessibilityValue("\(format(used)) used, \(format(available)) free, \(format(capacity)) total")
                HStack {
                    Label("\(format(used)) used", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                    Spacer()
                    Text("\(format(capacity)) total")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, StudioUpkeepDesign.Space.small)
    }

    private func softwareReading(_ title: String, symbol: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, StudioUpkeepDesign.Space.small)
    }

    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    private func formatMemory(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .memory) }
    private func format(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func sizeLabel(_ value: StorageMeasurement.Result?) -> String {
        guard let value else { return "Not measured" }
        return (value.incomplete ? "At least " : "") + format(value.bytes)
    }
    private func openSystemTool(_ id: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { status.failure = "This system tool could not be found."; return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { Task { @MainActor in status.failure = error.localizedDescription } }
        }
    }
}
