// SPDX-License-Identifier: MPL-2.0
import ProducerUpToDateCore
import SwiftUI

struct DAWInventoryView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(StudioUpkeepPreference.inventoryDensity)
    private var density = InventoryDensity.comfortable.rawValue


    var body: some View {
        let daws = model.visibleDAWs()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(daws.count == model.installedDAWs.count ? "\(daws.count) DAWs found" : "\(daws.count) of \(model.installedDAWs.count) DAWs")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(model.isScanning ? "Scanning…" : "Rescan") { model.startScan() }
                            .disabled(model.isScanning).tint(.primary)
                            .help("Scan installed software on this Mac. This does not check online.")
                    }
                    Text("Select a DAW to see its installed version and where to check for updates.")
                        .font(.caption).foregroundStyle(.secondary)
                    let storeInstalled = model.installedDAWs.filter { DAWUpdateSource.appStoreDestination(for: $0) != nil }
                    if !storeInstalled.isEmpty, let updates = URL(string: "macappstore://showUpdatesPage") {
                        HStack {
                            Text("App Store updates")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Open App Store") { NSWorkspace.shared.open(updates) }.help("Open the App Store to review and install updates.").controlSize(.small)
                        }
                    }
                }.padding(12)
                Divider()
                if model.installedDAWs.isEmpty {
                    InventoryEmptyView(section: .allDAWs)
                } else if daws.isEmpty {
                    SearchEmptyView()
                } else {
            Table(daws, selection: $model.selectedDAWID) {
                TableColumn("DAW") { daw in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(daw.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(daw.vendor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, rowPadding)
                }
                .width(min: 180, ideal: 260)

                TableColumn("Installed") { daw in
                    Text(daw.conciseInstalledVersion ?? "Unknown")
                        .font(.body.monospacedDigit())
                }
                .width(min: 80, ideal: 110)

                TableColumn("Update options") { daw in
                    Text(DAWUpdateSource.appStoreDestination(for: daw) != nil ? "App Store" : ProductDestinations.daw(daw)?.label ?? "Website not identified")
                }
                .width(min: 135, ideal: 180)

                TableColumn("Architecture") { daw in
                    Text(daw.architectureSummary)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 160)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if ids.count == 1, let id = ids.first, let daw = daws.first(where: { $0.id == id }) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([daw.path]) }.help("Reveal this location in Finder. Nothing is removed.")
                    Button("Review uninstall…") { model.cleanupDAW = daw }.help("Inspect files and review removal choices. Nothing is removed yet.").disabled(model.isScanning)
                }
            }
            }
        }
    }

    private var rowPadding: CGFloat {
        InventoryDensity(rawValue: density)?.rowPadding
            ?? InventoryDensity.comfortable.rowPadding
    }
}
