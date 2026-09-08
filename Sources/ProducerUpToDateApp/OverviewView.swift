// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

/// One screen that answers "how is my studio doing?" with the numbers the other sections
/// hold, each card opening its section. Every figure comes from the last local scan.
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport
    @StateObject private var macStatus = MacStatusModel()

    private var coverage: PluginUpdateCoverage { model.pluginCoverage }
    private func count(_ section: InventorySection) -> Int { model.products(in: section, report: report).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.large) {
                header
                MacStatusView(status: macStatus, report: report)
                Divider()
                grid("Health", cards: [
                    card(.needsAttention, value: count(.needsAttention), note: "Local findings such as Intel-only files or missing versions."),
                ])
                grid("Inventory", cards: [
                    card(.allPlugins, value: coverage.total, note: "Installed products grouped across plugin formats."),
                    card(.allDAWs, value: model.installedDAWs.count, note: "Applications found in the searched locations."),
                ])
                footer
            }
            .frame(maxWidth: 840, alignment: .leading)
            .padding(StudioUpkeepDesign.Space.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Studio overview").font(.title2.weight(.semibold))
            Text("Last scan \(report.finishedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if let changes = model.lastScanChanges, !changes.isEmpty {
                Text("Since the previous scan: \(changes.added.count) appeared, \(changes.removed.count) disappeared, \(changes.changed.count) changed version.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if report.inaccessibleLocationCount > 0 {
                Label("\(report.inaccessibleLocationCount) scan locations could not be read; the inventory is incomplete.", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Counts describe this Mac’s last scan. Select a product to see its installed files and update options. Scanning does not check online.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func grid(_ title: String, cards: [OverviewCard]) -> some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
            Text(title).font(.headline)
            VStack(spacing: 0) {
                ForEach(cards, id: \.section.id) { card in
                    card
                    Divider()
                }
            }
        }
    }

    private func card(_ section: InventorySection, value: Int, note: String) -> OverviewCard {
        OverviewCard(section: section, value: value, note: note) {
            model.navigate(to: section)
        }
    }
}

struct OverviewCard: View {
    let section: InventorySection
    let value: Int
    let note: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(section.rawValue, systemImage: section.symbolName).font(.subheadline.weight(.semibold))
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(value.formatted()).font(.title3.weight(.semibold)).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.rawValue), \(value.formatted()). \(note)")
        .accessibilityHint("Opens the \(section.rawValue) list")
    }
}
