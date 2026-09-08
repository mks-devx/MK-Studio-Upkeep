// SPDX-License-Identifier: MPL-2.0
import SwiftUI

@main
struct ProducerUpToDateApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var presence = AppPresenceController()
    @AppStorage(StudioUpkeepPreference.appearance)
    private var appearance = AppAppearance.system.rawValue
    @AppStorage(StudioUpkeepPreference.accent)
    private var accent = AppAccent.monochrome.rawValue

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .background(AppPresenceBridge(controller: presence, model: model))
                .tint(selectedAccent.color)
                .frame(minWidth: 1_180, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1_420, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan This Mac") {
                    model.startScan()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isScanning)
                Button("Export Inventory…") { model.exportInventory() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.currentReport == nil || model.isScanning)
            }

            CommandMenu("Navigate") {
                navigationButton("Overview", section: .overview, key: "0")
                navigationButton("Plugins", section: .allPlugins, key: "1")
                navigationButton("DAWs", section: .allDAWs, key: "2")
                navigationButton(
                    "Software Managers",
                    section: .managers,
                    key: "3"
                )
                navigationButton(
                    "Needs Attention",
                    section: .needsAttention,
                    key: "4"
                )
            }

            CommandGroup(after: .sidebar) {
                Button("Hardware") { model.navigate(to: .hardware) }
                Button("Drivers") { model.navigate(to: .drivers) }
                    .disabled(model.currentReport == nil)
                Button("Software Managers") { model.navigate(to: .managers) }
                    .disabled(model.currentReport == nil)
            }

            CommandGroup(replacing: .help) {
                Button("Report a bug…") { model.showsBugReport = true }
                Button("MK Studio Upkeep Manual") {
                    model.showsHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .tint(selectedAccent.color)
                .frame(width: 760, height: 560)
        }
    }

    private var selectedAccent: AppAccent {
        AppAccent(rawValue: accent) ?? .monochrome
    }

    private func navigationButton(
        _ title: String,
        section: InventorySection,
        key: KeyEquivalent
    ) -> some View {
        Button(title) {
            model.navigate(to: section)
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}

enum BrandColor {
    static var accent: Color {
        StudioUpkeepDesign.accent
    }
}
