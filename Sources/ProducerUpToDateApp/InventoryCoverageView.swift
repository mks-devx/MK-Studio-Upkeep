// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

struct InventoryCoverageView: View {
    @EnvironmentObject private var model: AppModel
    private enum Detail: String, Identifiable {
        case scope, explanation
        var id: String { rawValue }
    }
    @State private var detail: Detail?
    @AppStorage("showPluginCategories") private var showCategories = true
    let report: ScanReport
    let visibleCount: Int

    var body: some View {
        let coverage = model.pluginCoverage
        HStack(spacing: 12) {
            Text(countSummary(coverage))
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 12)
            Button(model.isScanning ? "Scanning…" : "Rescan") { model.startScan() }
                .disabled(model.isScanning)
                .help("Refresh installed software on this Mac. This does not check online.")
            Menu {
                Button("Export inventory…") { model.exportInventory() }
                Button("Scan details…") { detail = .scope }
                Button("About these results…") { detail = .explanation }
                Divider()
                Toggle("Show plugin categories", isOn: $showCategories)
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .fixedSize()
            .help("Export, scan details and display options.")

        }
        .sheet(item: $detail) { destination in
            if destination == .scope {
                ScanScopeView(report: report)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    checkDetails
                    HStack {
                        Spacer()
                        Button("Done") { detail = nil }.keyboardShortcut(.cancelAction)
                    }
                }.padding(24).frame(width: 440)
            }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func countSummary(_ coverage: PluginUpdateCoverage) -> String {
        if model.selectedSection == .updatesAvailable {
            return "\(model.visibleUpdates().count) of \(model.updateCount) updates"
        }
        return visibleCount == coverage.total ? "\(coverage.total) plugins" : "\(visibleCount) of \(coverage.total) plugins"
    }

    private var checkDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About these results").font(.headline)
            Text("The scan shows installed versions, file architecture and local compatibility findings.")
            Text("Select a product for its files, developer website or installed software manager. Website links come from a reviewed directory.")
            Text("Latest releases are not checked. Unknown websites and compatibility remain marked as unknown.")
        }.font(.subheadline)
    }
}

struct ScanScopeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let report: ScanReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scan details").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.help("Close this view.").keyboardShortcut(.cancelAction)
            }
            Text("\(report.records.count) plugin files · \(model.installedDAWs.count) DAW applications found")
                .font(.subheadline)
            if let changes = model.lastScanChanges, !changes.isEmpty {
                DisclosureGroup("Changes since the previous scan") {
                    ScanChangesView(changes: changes)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.dawWarnings.isEmpty || !model.dawScopeNotes.isEmpty {
                        Text("DAW search").font(.headline)
                        if !model.dawWarnings.isEmpty {
                            Text("Some locations could not be searched fully. Check the reasons below.")
                                .font(.subheadline)
                            DisclosureGroup("Search problems") {
                                ForEach(Array(Set(model.dawWarnings)).sorted(), id: \.self) { warning in
                                    Text(warning).font(.caption).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
                                }
                            }
                        }
                        if !model.dawScopeNotes.isEmpty {
                            Text("Deeply nested folders are outside the DAW search scope. A DAW stored there may be missing.")
                                .font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Folders beyond the search depth") {
                                ForEach(model.dawScopeNotes, id: \.self) { note in
                                    Text(note).font(.caption).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
                                }
                            }
                        }
                        Text("Plugin locations").font(.headline)
                        Divider()
                    }
                    ForEach(Array(report.locations.enumerated()), id: \.offset) { _, result in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(result.location.format.rawValue) · \(result.discoveredCount) files")
                                .font(.headline)
                            Text(result.location.url.path)
                                .font(.subheadline).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if !result.wasAccessible {
                                Text("This location could not be fully scanned.").foregroundStyle(.secondary)
                            }
                            if let error = result.errorDescription {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Plugin scanning includes enabled formats and configured folders. AAX, AUv3, DAW-internal devices and symbolic-link bundles are excluded. The DAW search checks application folders separately; adding plugin folders does not extend it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 560, height: 460)
    }
}
