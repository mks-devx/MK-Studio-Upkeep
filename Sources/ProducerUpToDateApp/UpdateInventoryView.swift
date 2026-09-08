// SPDX-License-Identifier: MPL-2.0
import ProducerUpToDateCore
import SwiftUI

struct UpdateInventoryView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(StudioUpkeepPreference.inventoryDensity)
    private var density = InventoryDensity.comfortable.rawValue

    var body: some View {
        let updates = model.visibleUpdates()
        if updates.isEmpty {
            if model.searchText.isEmpty {
                InventoryEmptyView(section: .updatesAvailable)
            } else {
                SearchEmptyView()
            }
        } else {
            Table(updates, selection: $model.selectedUpdateID) {
                TableColumn("Product") { update in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(update.vendor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, rowPadding)
                }
                .width(min: 160, ideal: 240)

                TableColumn("Type") { update in
                    Text(update.kind.rawValue)
                        .foregroundStyle(.secondary)
                }
                .width(min: 54, ideal: 70)

                TableColumn("Installed") { update in
                    Text(update.installedVersion)
                        .font(.body.monospacedDigit())
                }
                .width(min: 72, ideal: 96)

                TableColumn("Latest") { update in
                    Text(update.latestVersion)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(BrandColor.accent)
                }
                .width(min: 72, ideal: 96)

                TableColumn("Architecture") { update in
                    Text(update.architecture)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 155)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let id = ids.first, id.hasPrefix("plugin:"),
                   let product = model.pluginResult(String(id.dropFirst(7)))?.product {
                    PluginFinderMenu(bundles: product.bundles)
                    Button("Review uninstall…") { model.cleanupProduct = product }.help("Inspect files and review removal choices. Nothing is removed yet.").disabled(model.isScanning)
                } else if ids.count == 1, let id = ids.first,
                          let row = model.visibleUpdates().first(where: { $0.id == id }),
                          row.kind == .daw, let daw = model.daw(withID: String(row.id.dropFirst(4))) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([daw.path]) }.help("Reveal this location in Finder. Nothing is removed.")
                    Button("Review uninstall…") { model.cleanupDAW = daw }.help("Inspect files and review removal choices. Nothing is removed yet.").disabled(model.isScanning)
                }
            }
        }
    }

    private var rowPadding: CGFloat {
        InventoryDensity(rawValue: density)?.rowPadding
            ?? InventoryDensity.comfortable.rowPadding
    }
}
