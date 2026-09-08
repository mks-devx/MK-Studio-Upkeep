// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

@MainActor final class ManagerBrowser: ObservableObject {
    struct InstalledManager: Identifiable {
        let definition: ManagerDefinition
        let url: URL
        var id: String { definition.id }
    }
    @Published var installed: [InstalledManager] = []
    @Published var selection: String?
    @Published var search = ""
    @Published var failure: String?
    var filtered: [InstalledManager] {
        installed.filter { search.isEmpty || $0.definition.name.localizedCaseInsensitiveContains(search) }
    }
    var selected: InstalledManager? { filtered.first { $0.id == selection } }
    func refresh() {
        failure = nil
        installed = ManagerDefinition.known.compactMap { definition in
            guard let url = VendorAppLocator.locate(definition)?.url else { return nil }
            return InstalledManager(definition: definition, url: url)
        }.sorted { $0.definition.name.localizedStandardCompare($1.definition.name) == .orderedAscending }
        if selected == nil { selection = nil }
    }
    func open(_ item: InstalledManager) {
        failure = nil
        VendorAppLocator.open(item.url) { error in
            Task { @MainActor in self.failure = error?.localizedDescription }
        }
    }
}

struct ManagersView: View {
    @ObservedObject var browser: ManagerBrowser
    var body: some View {
        VStack(spacing: 0) {
            HStack {
            Text("\(browser.installed.count) software managers found. Open the apps that manage your audio software, updates and licences.")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                Button("Refresh") { browser.refresh() }.padding(.trailing, 16).help("Find installed software managers.")
            }
            Divider()
            List(selection: $browser.selection) {
                if browser.filtered.isEmpty {
                    Text(browser.installed.isEmpty ? "No recognised vendor apps found. Open a newly installed one once, then refresh." : "No managers match your search.")
                        .foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(["Software managers", "Hardware managers", "Licence tools"], id: \.self) { kind in
                    let rows = browser.filtered.filter { $0.definition.kind == kind }
                    if !rows.isEmpty {
                        Section(kind) {
                            ForEach(rows) { item in
                                Label(item.definition.name, systemImage: kind == "Licence tools" ? "key" : "square.stack.3d.up")
                                    .padding(.vertical, 6).tag(item.id)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { browser.refresh() }
        .onChange(of: browser.search) { _ in if browser.selected == nil { browser.selection = nil } }
    }
}

struct ManagerDetailView: View {
    @ObservedObject var browser: ManagerBrowser
    var body: some View {
        if let item = browser.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.definition.kind).font(.subheadline).foregroundStyle(.secondary)
                    Text(item.definition.name).font(.largeTitle.weight(.semibold))
                    Text(item.definition.kind == "Licence tools" ? "Handles licences and activation, not plugin updates." : "Open it to check for updates, downloads and activation.")
                        .foregroundStyle(.secondary)
                    Button("Open \(item.definition.name)") { browser.open(item) }.help("Open the installed vendor app to manage its products.")
                    if let failure = browser.failure { Text(failure).foregroundStyle(.secondary) }
                    Divider()
                    Text("Found through macOS app registration. That says nothing about which products you own or installed with it; no accounts or libraries are read.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    DisclosureGroup("Application details") {
                        Text(item.url.path).font(.caption).textSelection(.enabled)
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.help("Reveal this location in Finder.")
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up").font(.largeTitle)
                Text("Select a manager").font(.title2)
                Text("See its details and open it to manage your products. \(ManagerDefinition.known.count) vendor apps are recognised by their documented app names.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ManagerUpdateFallback: View {
    @EnvironmentObject private var model: AppModel
    let identifiers: [String]
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where to check").font(.headline)
            if let manager = ManagerDefinition.matching(identifiers: identifiers),
               let url = VendorAppLocator.locate(manager)?.url {
                Text("\(manager.name) is installed and delivers this vendor’s updates. Open it to check this product.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Open \(manager.name)") {
                    VendorAppLocator.open(url) { error in
                        Task { @MainActor in failure = error?.localizedDescription }
                    }
                }
                Text("Suggested from the plugin’s vendor identity; it may not be how you installed it.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let manager = ManagerDefinition.matching(identifiers: identifiers) {
                Text("\(manager.name) delivers this vendor’s updates, but it is not installed on this Mac.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let note = manager.note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let url = manager.url { Link("Get \(manager.name)", destination: url) }
            } else {
                Text("Check for updates inside the plugin or on the developer’s website.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let manager = ManagerDefinition.matching(identifiers: identifiers), let note = manager.note, VendorAppLocator.locate(manager) != nil {
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
