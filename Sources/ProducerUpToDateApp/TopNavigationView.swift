// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

/// Compact navigation keeps every inventory filter reachable without horizontal scrolling.
struct TopNavigationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIconView(size: 26)
                Text("MK Studio Upkeep").font(.headline)
                Spacer()
                Text("Developed by Mike Konstantinidis").font(.caption).foregroundStyle(.secondary)
                Link("GitHub support", destination: URL(string: "https://github.com/mks-devx/MK-Studio-Upkeep")!).font(.caption)
                navigationButton(.tips)
                Button { model.showsHelp = true } label: { Label("User Manual", systemImage: "book.closed") }.help("Open the built-in guide to scanning, updates and removal.")
            }
            HStack(spacing: 12) {
                navigationButton(.overview)
                navigationMenu("Your studio", sections: [.allPlugins, .allDAWs, .managers, .hardware, .drivers])
                reviewMenu
                navigationMenu("Maintenance", sections: [.caches])
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .padding(16)
        .studioPanelBackground()
    }
    private func navigationButton(_ section: InventorySection) -> some View {
        Button {
            model.navigate(to: section)
        } label: {
            Label(section.rawValue, systemImage: section.symbolName)
                .fontWeight(model.selectedSection == section ? .semibold : .regular)
        }
        .help("Show " + section.rawValue + ".")
        .accessibilityAddTraits(model.selectedSection == section ? .isSelected : [])
    }
    private func navigationMenu(_ title: String, sections: [InventorySection]) -> some View {
        Menu {
            Picker(title, selection: Binding(
                get: { model.selectedSection == .allPlugins ? (model.intelOnlyFilter && model.pluginStatusFilter == .allPlugins ? .intelOnly : model.pluginStatusFilter) : model.selectedSection },
                set: { value in
                    model.navigate(to: value)
                })) {
                ForEach(sections) { section in
                    Label(section.rawValue, systemImage: section.symbolName).tag(section)
                }
            }.pickerStyle(.inline)
        } label: {
            let selected = model.selectedSection == .allPlugins ? (model.intelOnlyFilter && model.pluginStatusFilter == .allPlugins ? .intelOnly : model.pluginStatusFilter) : model.selectedSection
            let active = sections.contains(selected) && model.localReviewFilter == .all
            Text(active ? selected.rawValue : title)
                .fontWeight(active ? .semibold : .regular)
        }
    }

    private var reviewMenu: some View {
        Menu {
            ForEach([InventorySection.needsAttention, .intelOnly]) { section in
                Button { model.navigate(to: section) } label: {
                    Label("\(section.rawValue) · \(model.products(in: section).count)", systemImage: section.symbolName)
                }
            }
            Divider()
            ForEach(LocalReviewFilter.navigationCases) { filter in
                Button { model.navigate(to: filter) } label: {
                    Label("\(filter.navigationTitle) · \(model.normalizedProducts.filter { model.matchesReview($0, filter: filter) }.count)",
                          systemImage: filter.navigationSymbol)
                }
            }
        } label: {
            Text(model.localReviewFilter != .all ? model.localReviewFilter.navigationTitle
                 : model.selectedSection == .needsAttention ? InventorySection.needsAttention.rawValue
                 : model.selectedSection == .allPlugins && model.intelOnlyFilter ? InventorySection.intelOnly.rawValue : "Review")
        }
    }
}
