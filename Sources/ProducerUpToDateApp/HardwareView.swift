// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

@MainActor final class HardwareBrowser: ObservableObject {
    enum Group: String, CaseIterable, Identifiable {
        case audio = "Audio interfaces and outputs"
        case midi = "MIDI devices and controllers"
        case drivers = "Drivers"
        var id: String { rawValue }
        var explanation: String {
            switch self {
            case .audio: "Everything macOS can play or record through right now, including built-in speakers and monitors."
            case .midi: "Controllers and MIDI interfaces macOS knows about. Saved entries stay listed after you unplug a device."
            case .drivers: "Audio and MIDI driver software installed on this Mac. Each entry says who made it and where its updates come from."
            }
        }
    }
    struct Item: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let group: Group
        var audio: AudioHardwareRecord? = nil
        var midi: MIDIHardwareRecord? = nil
        var driver: DriverRecord? = nil
        /// One line under the name: where updates come from, or that none is known.
        var routeLine: String {
            if let driver { return DriverDescription.route(for: driver) }
            if let audio {
                if audio.isBuiltIn { return "Updated with macOS" }
                if audio.transport == "Virtual device" || audio.transport == "Aggregate device" { return "Software device · no firmware" }
                return audio.guide.map { "Updates: \($0.updateRoute)" } ?? "No reviewed update route · check the maker's website"
            }
            if let midi {
                if midi.isSystemVirtual { return "Provided by macOS" }
                let status = midi.offline.map { $0 ? "Saved entry, not available" : "Available to MIDI apps" } ?? "Availability unknown"
                return status + " · " + (midi.guide.map { "updates: \($0.updateRoute)" } ?? "no reviewed update route")
            }
            return ""
        }
    }
    let driversOnly: Bool
    init(driversOnly: Bool = false) { self.driversOnly = driversOnly }
    var groups: [Group] { driversOnly ? [.drivers] : [.audio, .midi] }

    @Published var report: HardwareScanReport?
    @Published var isScanning = false
    @Published var failure: String?
    @Published var selection: String?
    @Published var search = ""
    @Published var filter: Group?
    var task: Task<Void, Never>?

    var items: [Item] {
        guard let report else { return [] }
        let audio = report.devices.map { Item(id: "audio-\($0.id)", name: $0.name, subtitle: "\($0.manufacturer) · \($0.transport)", group: .audio, audio: $0) }
        let midi = report.midiDevices
            .sorted { ($0.isSystemVirtual ? 1 : 0, $0.offline == true ? 1 : 0, $0.name) < ($1.isSystemVirtual ? 1 : 0, $1.offline == true ? 1 : 0, $1.name) }
            .map { Item(id: "midi-\($0.id)", name: $0.name, subtitle: $0.isSystemVirtual ? "macOS" : $0.manufacturer.isEmpty ? "Unknown maker" : $0.manufacturer, group: .midi, midi: $0) }
        let drivers = report.drivers.map { Item(id: "driver-\($0.id)", name: $0.name, subtitle: DriverDescription.maker(of: $0) + " · " + ($0.version ?? "unknown version"), group: .drivers, driver: $0) }
        return audio + midi + drivers
    }
    func items(in group: Group) -> [Item] {
        items.filter { groups.contains(group) && $0.group == group && (filter == nil || filter == group)
            && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search)
                || ($0.driver?.bundleIdentifier ?? "").localizedCaseInsensitiveContains(search)) }
    }
    var filtered: [Item] { groups.flatMap { items(in: $0) } }
    var availableMIDICount: Int { report?.midiDevices.filter { !$0.isSystemVirtual && $0.offline == false }.count ?? 0 }
    func protection(of driver: DriverRecord) -> RemovalProtection { DriverProtection.assess(driver, devices: report?.devices ?? []) }
    var selected: Item? { filtered.first { $0.id == selection } }
    func reconcileSelection() { if selected == nil { selection = nil } }
    func scan() {
        guard !isScanning else { return }
        isScanning = true; failure = nil
        task = Task {
            let worker = Task.detached(priority: .userInitiated) { try HardwareScanner.scan() }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                report = result
                reconcileSelection()
            } catch is CancellationError { }
            catch { failure = error.localizedDescription }
            isScanning = false
        }
    }
}

struct HardwareView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var browser: HardwareBrowser
    @State private var removalDriver: DriverRecord?
    @State private var midiRemoval: [MIDIHardwareRecord]?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(summary).font(.subheadline)
                    Spacer()
                    Button(browser.isScanning ? "Scanning…" : "Rescan") { browser.scan() }.disabled(browser.isScanning)
                        .help(browser.driversOnly ? "Refresh installed drivers and device protection checks. This does not check online." : "Refresh audio and MIDI devices. This does not check online.")
                    if browser.isScanning {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { browser.task?.cancel() }.help("Stop this operation or close this view.")
                    }
                }
                if !browser.driversOnly {
                    Picker("Show", selection: $browser.filter) {
                        Text("Everything").tag(HardwareBrowser.Group?.none)
                        ForEach(browser.groups) { group in
                            Text("\(group == .audio ? "Audio" : group == .midi ? "MIDI entries" : "Drivers") · \(browser.items.filter { $0.group == group }.count)").tag(HardwareBrowser.Group?.some(group))
                        }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                if !browser.driversOnly && (browser.filter == nil || browser.filter == .midi) {
                    let stale = browser.items(in: .midi).compactMap(\.midi).filter { MIDICleanup.isRemovable($0) }
                    if !stale.isEmpty {
                        Button("Review \(stale.count) disconnected MIDI entries…") { midiRemoval = stale }
                            .controlSize(.small)
                            .help("Review saved entries for disconnected MIDI devices. Nothing is removed until you confirm.")
                    }
                }
                if let failure = browser.failure { Text(failure).foregroundStyle(.secondary) }
            }.padding(16)
            Divider()
            List(selection: $browser.selection) {
                if browser.filtered.isEmpty {
                    Text(browser.isScanning ? (browser.driversOnly ? "Looking for installed drivers…" : "Looking for audio and MIDI devices…") : "Nothing matches. Clear the search or scan again.")
                        .foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(browser.groups) { group in
                    let rows = browser.items(in: group)
                    if !rows.isEmpty {
                        Section {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.explanation).font(.caption).foregroundStyle(.secondary).textCase(nil)
                                }

                            }
                            .accessibilityElement(children: .contain)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 6)
                            .listRowSeparator(.hidden)
                            ForEach(rows) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(item.name).fontWeight(.medium)
                                        if let midi = item.midi, MIDICleanup.protection(midi).isRed, !midi.isSystemVirtual {
                                            Label(midi.offline == false ? "Available" : "Availability unknown", systemImage: "cable.connector")
                                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                        }
                                        if let driver = item.driver, browser.protection(of: driver).isRed {
                                            Label("Don’t delete", systemImage: "exclamationmark.octagon.fill")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(StudioUpkeepDesign.protection)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(StudioUpkeepDesign.protection.opacity(0.12), in: Capsule())
                                                .accessibilityLabel("Warning: don’t delete this driver")
                                        }
                                        if let driver = item.driver {
                                            let state = DriverUpdateEvaluator.evaluate(driver, catalogue: model.catalogue?.drivers ?? [])
                                            if state != .notChecked {
                                                Text(state.rawValue).font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(state == .updateAvailable ? BrandColor.accent.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
                                            }
                                        }
                                    }
                                    Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                                    Text(item.routeLine).font(.caption).foregroundStyle(.secondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 58, alignment: .leading)
                                .padding(.vertical, 5).tag(item.id)
                                .accessibilityElement(children: .combine)
                                .contextMenu {
                                    if let driver = item.driver {
                                        let protection = browser.protection(of: driver)
                                        if protection.isRed {
                                            Button("Don’t delete this · " + (DriverProtection.isSystemComponent(bundleIdentifier: driver.bundleIdentifier, path: driver.path) ? "part of macOS" : "a device or the system depends on it")) {}.disabled(true)
                                        }
                                        if !DriverProtection.isSystemComponent(bundleIdentifier: driver.bundleIdentifier, path: driver.path) {
                                            Button(CleanupPlanner().plan(for: driver).items.isEmpty || protection.isRed ? "Removal instructions…" : "Review removal…") {
                                                browser.selection = item.id
                                                removalDriver = driver
                                            }
                                        }
                                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([driver.path]) }.help("Reveal this location in Finder. Nothing is removed.")
                                    } else {
                                        if let midi = item.midi {
                                            if MIDICleanup.isRemovable(midi) {
                                                Button("Remove saved entry…") { browser.selection = item.id; midiRemoval = [midi] }.help("Review forgetting this offline MIDI entry. Its saved name and port setup will be lost.")
                                            } else if let reason = MIDICleanup.protection(midi).reason, !midi.isSystemVirtual {
                                                Button("Can’t remove · " + reason.prefix(40) + "…") {}.disabled(true)
                                            }
                                        }
                                        if let guide = item.audio?.guide ?? item.midi?.guide, let app = VendorAppLocator.locate(guide) {
                                            Button("Open \(app.name)") { VendorAppLocator.open(app.url) { _ in } }
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(group.rawValue)
                        }
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 76)
            if let report = browser.report, !report.warnings.isEmpty {
                DisclosureGroup("Some locations could not be read") {
                    ScrollView { VStack(alignment: .leading) { ForEach(report.warnings, id: \.self) { Text($0).font(.caption) } } }.frame(maxHeight: 100)
                }.padding(16)
            }
        }
        .onAppear { if browser.report == nil { browser.scan() } }
        .onChange(of: browser.filter) { _ in browser.reconcileSelection() }
        .onChange(of: browser.search) { _ in browser.reconcileSelection() }
        .onDisappear { browser.task?.cancel() }
        .sheet(item: $removalDriver) { driver in DriverRemovalSheet(driver: driver, browser: browser) }
        .sheet(isPresented: Binding(get: { midiRemoval != nil }, set: { if !$0 { midiRemoval = nil } })) {
            MIDIRemovalSheet(devices: midiRemoval ?? [], browser: browser)
        }
    }

    private var summary: String {
        guard let report = browser.report else { return browser.isScanning ? "Scanning…" : "Not scanned yet" }
        if browser.driversOnly { return "\(report.drivers.count) installed drivers" }
        return "\(report.devices.count) audio devices · \(report.midiDevices.count) MIDI entries (available entries: \(browser.availableMIDICount))"
    }
}

struct HardwareDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var browser: HardwareBrowser
    @State private var removalDriver: DriverRecord?
    @State private var midiRemoval: [MIDIHardwareRecord]?
    var body: some View {
        Group {
            if let item = browser.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(item.group.rawValue).font(.subheadline).foregroundStyle(.secondary)
                        Text(item.name).font(.largeTitle.weight(.semibold))
                        Text(item.subtitle).foregroundStyle(.secondary)
                        if let device = item.audio { audioSection(device) }
                        if let device = item.midi { midiSection(device) }
                        if let driver = item.driver { driverSection(driver) }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: browser.driversOnly ? "puzzlepiece.extension" : "hifispeaker").font(.largeTitle).accessibilityHidden(true)
                    Text(browser.driversOnly ? "Select a driver" : "Select a device").font(.title2)
                    Text(browser.driversOnly ? "See its maker, update options and removal guidance." : "See its connection, device details and firmware update options.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $removalDriver) { driver in DriverRemovalSheet(driver: driver, browser: browser) }
        .sheet(isPresented: Binding(get: { midiRemoval != nil }, set: { if !$0 { midiRemoval = nil } })) {
            MIDIRemovalSheet(devices: midiRemoval ?? [], browser: browser)
        }
    }

    @ViewBuilder private func updateRoute(_ guide: HardwareVendorGuide?, builtIn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Firmware and driver updates").font(.headline)
            if builtIn {
                Text("Apple updates built-in audio together with macOS. There is nothing separate to check.")
            } else if let guide {
                Text("\(guide.vendor) delivers updates through \(guide.updateRoute).")
                if let note = guide.note { Text(note).foregroundStyle(.secondary) }
                HStack {
                    if let app = VendorAppLocator.locate(guide) {
                        Button("Open \(app.name)") { VendorAppLocator.open(app.url) { _ in } }
                    } else if let name = guide.managerAppName {
                        Text("\(name) is not installed on this Mac.").font(.caption).foregroundStyle(.secondary)
                        if let url = guide.url { Link("Get \(name)", destination: url) }
                    }
                    if let url = guide.url { Link("Official downloads and support", destination: url) }
                }
                Text("MK Studio Upkeep does not read firmware versions, so it cannot say whether an update is waiting. The vendor's tool can.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No reviewed update route for this maker yet. Check the maker's website or the app that came with the device.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func audioSection(_ device: AudioHardwareRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Connection", value: device.transport)
            LabeledContent("Device sample rate", value: device.sampleRate.map { String(format: "%.1f kHz", $0 / 1_000) } ?? "Unavailable")
            LabeledContent("Device buffer", value: device.bufferFrames.map { "\($0) frames" } ?? "Unavailable")
            Text("Read from Core Audio at scan time. Your DAW may request a different buffer; check its audio settings.").font(.caption).foregroundStyle(.secondary)
            if device.transport == "Virtual device" || device.transport == "Aggregate device" {
                Text("A software device created by an app or by Audio MIDI Setup. It has no firmware of its own.").foregroundStyle(.secondary)
            } else {
                updateRoute(device.guide, builtIn: device.isBuiltIn)
            }
            Text("Reported by Core Audio. MK Studio Upkeep reads names, connection types, sample rate and buffer size; it does not read serial numbers or firmware.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func midiSection(_ device: MIDIHardwareRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if device.isSystemVirtual {
                Text("Part of macOS: a virtual MIDI connection between apps or over the network. Nothing to update or remove.").foregroundStyle(.secondary)
            } else {
                LabeledContent("Status", value: device.offline.map { $0 ? "Saved entry · not connected right now" : "Available to MIDI apps" } ?? "Unknown")
                updateRoute(device.guide, builtIn: false)
                Text("Reported by Core MIDI. Saved entries stay listed after a device is unplugged; availability does not prove a physical connection or recent use.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Removing the saved entry").font(.headline)
                    if MIDICleanup.isRemovable(device) {
                        Text(MIDICleanup.consequence).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Remove saved entry…") { midiRemoval = [device] }.help("Review forgetting this offline MIDI entry. Its saved name and port setup will be lost.")
                    } else if let reason = MIDICleanup.protection(device).reason {
                        Text(reason).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func driverSection(_ driver: DriverRecord) -> some View {
        let state = DriverUpdateEvaluator.evaluate(driver, catalogue: model.catalogue?.drivers ?? [])
        let protection = browser.protection(of: driver)
        return VStack(alignment: .leading, spacing: 16) {
            if protection.isRed, let reason = protection.reason { DoNotDeleteBanner(reason: reason) }
            VStack(alignment: .leading, spacing: 8) {
                Text("What this is").font(.headline)
                Text(DriverDescription.describe(driver)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Version").font(.headline)
                Text(state == .notChecked ? "Installed \(driver.version ?? "unknown version"). Check the maker’s app or website for current releases." : "\(state.rawValue) · installed \(driver.version ?? "unknown version")")
                if let release = model.catalogue?.drivers.first(where: { $0.bundleIdentifier == driver.bundleIdentifier }) {
                    Text("Reviewed release \(release.latestVersion), checked \(release.checkedOn).").font(.caption).foregroundStyle(.secondary)
                    Link("Official driver downloads", destination: release.sourceURL)
                }
            }
            updateRoute(HardwareVendorGuide.matching(bundleIdentifier: driver.bundleIdentifier), builtIn: (driver.bundleIdentifier ?? "").hasPrefix("com.apple."))
            if let provenance = driver.provenance {
                Text(provenance.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if HardwareVendorGuide.matching(bundleIdentifier: driver.bundleIdentifier) == nil, driver.provenance?.signature != .apple {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Copy details for the maintainer") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(DriverDescription.maintainerReport(for: driver), forType: .string)
                    }
                    Text("Copies the driver’s name, kind, identifier, version, standard folder and signing information. Review the text for private details before sharing it in a report.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            TechnicalDetailsDisclosure {
                VStack(alignment: .leading, spacing: 4) {
                    Text(driver.path.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(driver.bundleIdentifier ?? "Unknown identifier").font(.caption).textSelection(.enabled)
                    Text(driver.kind).font(.caption)
                }
            }
            if !DriverProtection.isSystemComponent(bundleIdentifier: driver.bundleIdentifier, path: driver.path) {
                let plan = CleanupPlanner().plan(for: driver)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Removing it").font(.headline)
                    if case let .caution(reason) = protection { Text(reason).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Text(plan.items.isEmpty || protection.isRed
                         ? (protection.isRed ? "This driver is marked Don’t delete this while a device relies on it. Use the maker’s uninstaller or updater instead." : plan.excludedUserContentDescription)
                         : "You can move this driver bundle to the Trash after a preview and a five-second hold. The review names the devices that likely depend on it. Finder will ask for your administrator password.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(plan.items.isEmpty || protection.isRed ? "Removal instructions…" : "Review removal…") { removalDriver = driver }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([driver.path]) }.help("Reveal this location in Finder. Nothing is removed.")
                    }
                }
            }
        }
    }
}


/// Finds a vendor app by bundle identifier first, then by name in the Applications folders,
/// so setups with different app versions or install locations still get an Open button.
enum VendorAppLocator {
    struct Located { let name: String; let url: URL }

    /// Opens a vendor app only if it carries a verified Developer ID, App Store or Apple signature,
    /// The user also reviews the actual signer; an expected-vendor mapping is not yet available.
    /// Checked at click time; locating apps for display stays cheap.
    static func open(_ url: URL, completion: @escaping @Sendable (Error?) -> Void) {
        Task.detached(priority: .userInitiated) {
            let provenance = BundleProvenance.read(at: url)
            let trusted = [.developerID, .macAppStore, .apple].contains(provenance.signature)
            await MainActor.run {
                guard trusted else {
                    let message = "\(url.deletingPathExtension().lastPathComponent) does not carry a verified developer signature, so it was not opened. Open it from the Applications folder if you trust it."
                    let alert = NSAlert()
                    alert.messageText = "Not opened"
                    alert.informativeText = message
                    alert.runModal()
                    completion(NSError(domain: "StudioUpkeep.VendorApp", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
                    return
                }
                // A trusted signature is not proof of the expected vendor. Let the user review
                // the actual publisher instead of silently asserting a name-based match.
                let confirmation = NSAlert()
                confirmation.messageText = "Open \(url.deletingPathExtension().lastPathComponent)?"
                confirmation.informativeText = "Signed by \(provenance.signer ?? "an identified developer"). The signature is valid, but MK Studio Upkeep has no verified publisher mapping for this manager. Check that this is the publisher you expect."
                confirmation.addButton(withTitle: "Open Application")
                confirmation.addButton(withTitle: "Cancel")
                guard confirmation.runModal() == .alertFirstButtonReturn else { completion(nil); return }
                NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in completion(error) }
            }
        }
    }
    static func locate(_ guide: HardwareVendorGuide) -> Located? {
        locate(bundleIdentifier: guide.managerBundleIdentifier, appName: guide.managerAppName)
    }
    static func locate(_ manager: ManagerDefinition) -> Located? {
        manager.appNames.lazy.compactMap { locate(bundleIdentifier: nil, appName: $0) }.first
    }
    static func locate(bundleIdentifier: String?, appName: String?) -> Located? {
        if let id = bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           FileManager.default.fileExists(atPath: url.path) {
            return Located(name: appName ?? url.deletingPathExtension().lastPathComponent, url: url)
        }
        guard let name = appName else { return nil }
        // Launch Services also knows registered apps in vendor subfolders or other volumes.
        // Name lookup is only discovery; opening still verifies the signature and asks the user.
        if let path = NSWorkspace.shared.fullPath(forApplication: name),
           FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist").path) {
            return Located(name: name, url: URL(fileURLWithPath: path))
        }
        let folders = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for folder in folders {
            let candidate = folder.appendingPathComponent(name + ".app")
            guard FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Contents/Info.plist").path) else { continue }
            // A matching name is not identity; `open` verifies the signature before launching.
            return Located(name: name, url: candidate)
        }
        return nil
    }
}

/// Driver removal uses the same preview, related-files search and hold-to-confirm flow as
/// plugins, with a preface that says what the driver is and which devices likely rely on it.
struct DriverRemovalSheet: View {
    let driver: DriverRecord
    @ObservedObject var browser: HardwareBrowser
    var body: some View {
        let plan = CleanupPlanner().plan(for: driver)
        let protection = browser.protection(of: driver)
        // A red protection is binding: the sheet shows what the driver is and the maker's route,
        // never a removal control.
        if plan.items.isEmpty || protection.isRed {
            DriverRemovalReview(driver: driver, protection: protection)
        } else {
            CleanupActionView(plan: plan, identifiers: [driver.bundleIdentifier].compactMap { $0 }, reviewOnly: true,
                              preface: preface, onCompleted: { browser.scan() },
                              criticalWarning: protection.isRed ? protection.reason : nil)
        }
    }
    private var preface: [String] {
        var lines = [DriverDescription.describe(driver)]
        if case let .caution(reason) = browser.protection(of: driver) { lines.append(reason) }
        lines.append("The driver folder belongs to macOS, so Finder performs the move and asks for your administrator password. Nothing else is sent to Finder.")
        return lines
    }
}


/// Forgets saved entries for disconnected MIDI devices after a review and a five-second hold.
/// Nothing on disk changes; reconnecting a device recreates its entry.
struct MIDIRemovalSheet: View {
    let devices: [MIDIHardwareRecord]
    @ObservedObject var browser: HardwareBrowser
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UInt32> = []
    @State private var confirmed = false
    @State private var result: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(devices.count == 1 ? "Remove saved MIDI entry" : "Remove saved MIDI entries").font(.title2.weight(.semibold))
            Label(MIDICleanup.consequence, systemImage: "info.circle").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(devices) { device in
                    Toggle(isOn: Binding(get: { selected.contains(device.id) }, set: { if $0 { selected.insert(device.id) } else { selected.remove(device.id) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).fontWeight(.medium)
                            Text(device.manufacturer.isEmpty ? "Unknown maker · not connected" : "\(device.manufacturer) · not connected").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(!MIDICleanup.isRemovable(device))
                }
            }.frame(minHeight: 120)
            Toggle("I understand these devices will need to be set up again if I reconnect them", isOn: $confirmed)
            if let result { Text(result).font(.caption).foregroundStyle(.secondary) }
            if !TestedPlatform.isTestedConfiguration {
                Text(TestedPlatform.removalCaution).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if selected.isEmpty { Text("Select at least one saved entry above.").font(.caption) }
            else if !confirmed { Text("Acknowledge the setup warning above to continue.").font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }.help("Stop this operation or close this view.")
                Spacer()
                Text("\(selected.count) selected").font(.caption)
                HoldToTrashButton(enabled: TestedPlatform.removalAllowed && confirmed && !selected.isEmpty, title: confirmed && !selected.isEmpty ? "Hold 5 seconds, then release to remove" : "Complete the review above", readyTitle: "Release to remove the saved entries") {
                    guard TestedPlatform.removalAllowed else { result = TestedPlatform.removalUnavailable; return }
                    var failures: [String] = []
                    for device in devices where selected.contains(device.id) {
                        do { try MIDICleanup.remove(device) } catch { failures.append("\(device.name): \(error.localizedDescription)") }
                    }
                    browser.scan()
                    if failures.isEmpty { dismiss() } else { result = failures.joined(separator: "\n") }
                }.frame(width: 320, height: 32).id(selected.count.description + String(confirmed))
            }
        }
        .padding(24).frame(width: 640, height: 480)
    }
}
