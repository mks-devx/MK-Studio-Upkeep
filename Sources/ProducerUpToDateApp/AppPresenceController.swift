// SPDX-License-Identifier: BUSL-1.1
import AppKit
import Combine
import ProducerUpToDateCore
import SwiftUI

/// A native status menu handles both mouse buttons and remains available after the main window closes.
@MainActor final class AppPresenceController: NSObject, ObservableObject, NSMenuDelegate {
    private lazy var brandMark = makeBrandMark()
    private var item: NSStatusItem?
    private weak var model: AppModel?
    private var openMain: (() -> Void)?
    private var openPreferences: (() -> Void)?
    private var preferences: AnyCancellable?
    private var updates: AnyCancellable?
    private var audioTask: Task<Void, Never>?
    private var audioOutput: AudioOutputSnapshot?
    private var audioHasRead = false

    func configure(model: AppModel, openMain: @escaping () -> Void, openPreferences: @escaping () -> Void) {
        // Use the same packaged artwork as the sidebar, including for local test builds.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        self.model = model; self.openMain = openMain; self.openPreferences = openPreferences
        guard preferences == nil else { apply(); return }
        preferences = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        updates = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.updateLabel() }
        }
        apply()
    }
    private func flag(_ key: String, fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    private func apply() {
        // A single AppKit override avoids SwiftUI retaining the last explicit scheme
        // when preferredColorScheme changes back to nil. nil inherits macOS live.
        let appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: StudioUpkeepPreference.appearance) ?? "system") ?? .system
        let desired: NSAppearance? = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance?.name != desired?.name { NSApp.appearance = desired }

        let visibility = AppVisibility(dock: flag("showDockIcon", fallback: true), menuBar: flag("showMenuBar", fallback: true))
        if !flag("showDockIcon", fallback: true) && visibility.dock { UserDefaults.standard.set(true, forKey: "showDockIcon") }
        let policy: NSApplication.ActivationPolicy = visibility.dock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        if visibility.menuBar && item == nil {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item?.button?.target = self
            item?.button?.action = #selector(showMenu)
            item?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else if !visibility.menuBar, let existing = item {
            NSStatusBar.system.removeStatusItem(existing); item = nil
        }
        configureAudioReadings()
        updateLabel()
    }
    private func configureAudioReadings() {
        let enabled = item != nil && flag(MenuBarAudioSummary.preferenceKey, fallback: true)
        guard enabled else {
            audioTask?.cancel(); audioTask = nil
            audioOutput = nil; audioHasRead = false
            return
        }
        guard audioTask == nil else { return }
        audioTask = Task { [weak self] in
            while !Task.isCancelled {
                let worker = Task.detached(priority: .utility) { AudioOutputSnapshot.read() }
                let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, let self else { return }
                self.audioOutput = result; self.audioHasRead = true
                self.updateLabel()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }
    private func updateLabel() {
        guard let model, let button = item?.button else { return }
        button.image = brandMark
        button.setAccessibilityLabel("MK Studio Upkeep")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        let showAudio = flag(MenuBarAudioSummary.preferenceKey, fallback: true)
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        button.title = showAudio ? " " + (audioHasRead ? MenuBarAudioSummary.title(for: audioOutput) : "Reading audio…") : ""
        let detail = showAudio ? "\n" + (audioHasRead ? MenuBarAudioSummary.detail(for: audioOutput) : "Reading macOS output settings…") : ""
        button.toolTip = "MK Studio Upkeep · " + model.menuBarStatus + detail
        button.setAccessibilityLabel("MK Studio Upkeep" + detail)
    }
    /// Small-size rendering of the six signal rails. An alpha-only silhouette avoids
    /// treating the opaque app-icon tile as a filled status-bar template.
    private func makeBrandMark() -> NSImage? {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let rails: [[NSPoint]] = [
                [.init(x: 1, y: 11), .init(x: 4, y: 14), .init(x: 15, y: 14), .init(x: 12, y: 11)],
                [.init(x: 15, y: 13), .init(x: 18, y: 16), .init(x: 22, y: 16), .init(x: 19, y: 13)],
                [.init(x: 1, y: 6), .init(x: 4, y: 9), .init(x: 13, y: 9), .init(x: 10, y: 6)],
                [.init(x: 13, y: 8), .init(x: 16, y: 11), .init(x: 22, y: 11), .init(x: 19, y: 8)],
                [.init(x: 1, y: 1), .init(x: 4, y: 4), .init(x: 10, y: 4), .init(x: 7, y: 1)],
                [.init(x: 10, y: 3), .init(x: 13, y: 6), .init(x: 22, y: 6), .init(x: 19, y: 3)]
            ]
            for points in rails {
                let path = NSBezierPath()
                path.move(to: points[0])
                for point in points.dropFirst() { path.line(to: point) }
                path.close(); path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func showMenu() {
        guard let model else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "MK Studio Upkeep · " + model.menuBarStatus, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        add("Open MK Studio Upkeep", #selector(openWindow), to: menu)
        add(model.isScanning ? "Cancel Scan" : "Scan This Mac", #selector(scan), to: menu)
        add("Check for Updates…", #selector(checkForAppUpdates), to: menu)
            .toolTip = "Open GitHub Releases for MK Studio Upkeep. Private releases require signing in with repository access."
        add("Settings…", #selector(settings), to: menu)
        menu.addItem(.separator())
        let dock = add("Show Dock icon", #selector(toggleDock), to: menu)
        dock.state = flag("showDockIcon", fallback: true) ? .on : .off
        add("Hide menu-bar icon", #selector(hideMenuBar), to: menu)
        menu.addItem(.separator())
        add("Quit MK Studio Upkeep", #selector(quit), to: menu)
        guard let button = item?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
    @discardableResult private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
        value.target = self; menu.addItem(value); return value
    }
    @objc private func checkForAppUpdates() {
        let source = AppReleaseCheck.Source(Bundle.main.object(forInfoDictionaryKey: "StudioUpkeepReleaseRepository") as? String)
            ?? AppReleaseCheck.projectSource
        guard !NSWorkspace.shared.open(source.releasesURL) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn’t open the release page"
        alert.informativeText = "Open this address in your browser to check for MK Studio Upkeep updates:\n" + source.releasesURL.absoluteString
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    @objc private func openWindow() { openMain?(); NSApp.activate(ignoringOtherApps: true) }
    @objc private func scan() { if model?.isScanning == true { model?.cancelScan() } else { model?.startScan() } }
    @objc private func settings() {
        openWindow()
        openPreferences?()
    }
    @objc private func toggleDock() { UserDefaults.standard.set(!flag("showDockIcon", fallback: true), forKey: "showDockIcon"); apply() }
    @objc private func hideMenuBar() { UserDefaults.standard.set(true, forKey: "showDockIcon"); UserDefaults.standard.set(false, forKey: "showMenuBar"); apply(); openWindow() }
    @objc private func quit() { NSApp.terminate(nil) }
}

struct AppPresenceBridge: View {
    @ObservedObject var controller: AppPresenceController
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if #available(macOS 14, *) {
            ModernPresenceBridge(controller: controller, model: model)
        } else {
            Color.clear.frame(width: 0, height: 0).onAppear {
                controller.configure(model: model, openMain: { openWindow(id: "main") }, openPreferences: {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                })
            }
        }
    }
}

@available(macOS 14, *)
private struct ModernPresenceBridge: View {
    let controller: AppPresenceController
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            controller.configure(model: model, openMain: { openWindow(id: "main") }, openPreferences: { openSettings() })
        }
    }
}
