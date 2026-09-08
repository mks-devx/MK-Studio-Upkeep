// SPDX-License-Identifier: MPL-2.0
import ProducerUpToDateCore
import SwiftUI

/// The overview's right-hand panel: what this scan covered and where its evidence comes from.
struct OverviewDetailView: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport
    @State private var showsScope = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.regular) {
                Text("About this scan").font(.title3.weight(.semibold))
                LabeledContent("Completed", value: report.finishedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Locations", value: "\(report.locations.count) scanned" + (report.inaccessibleLocationCount > 0 ? ", \(report.inaccessibleLocationCount) unreadable" : ""))
                LabeledContent("Files", value: report.records.count.formatted())
                LabeledContent("This Mac", value: MacArchitecture.current.processor.rawValue)
                Text("Installed software was inspected without loading plugins. Website matching is local; scan results are not uploaded.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Scan details") { showsScope = true }.help("See which locations the scan includes and any limitations.")
                    Button("Export inventory…") { model.exportInventory() }.help("Choose where to save an inventory report.")
                    Button("Rescan") { model.startScan() }.help("Read the installed inventory again without changing software.").disabled(model.isScanning)
                }
                .controlSize(.small)
            }
            .padding(StudioUpkeepDesign.Space.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showsScope) { ScanScopeView(report: report) }
    }
}
