// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

struct SidebarView: View {
    private enum Destination: Hashable {
        case inventory(InventorySection)
        case review(LocalReviewFilter)
    }
    @EnvironmentObject private var model: AppModel
    let report: ScanReport
    @State private var showsScanDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: StudioUpkeepDesign.Space.medium) {
                AppIconView(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MK Studio Upkeep")
                        .font(.headline)
                    Text("Studio software health")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, StudioUpkeepDesign.Space.regular)
            .padding(.top, StudioUpkeepDesign.Space.medium)
            .padding(.bottom, StudioUpkeepDesign.Space.regular)

            Divider()

            List(selection: Binding<Destination?>(
                get: {
                    if model.selectedSection == .allPlugins, model.localReviewFilter != .all {
                        return .review(model.localReviewFilter)
                    }
                    let section = model.selectedSection == .allPlugins
                        ? (model.intelOnlyFilter ? .intelOnly : model.pluginStatusFilter)
                        : model.selectedSection
                    return .inventory(section)
                },
                set: { value in
                    guard let value else { return }
                    switch value {
                    case .inventory(let section): model.navigate(to: section)
                    case .review(let filter): model.navigate(to: filter)
                    }
                }
            )) {
                Section {
                    Label(InventorySection.overview.rawValue, systemImage: InventorySection.overview.symbolName)
                        .tag(Destination.inventory(InventorySection.overview))
                }

                Section("Your studio") {
                    sidebarRow(.allPlugins)
                    sidebarRow(.allDAWs)
                    Label(InventorySection.managers.rawValue, systemImage: InventorySection.managers.symbolName)
                        .tag(Destination.inventory(InventorySection.managers))
                    Label(InventorySection.hardware.rawValue, systemImage: InventorySection.hardware.symbolName)
                        .tag(Destination.inventory(InventorySection.hardware))
                    Label(InventorySection.drivers.rawValue, systemImage: InventorySection.drivers.symbolName)
                        .tag(Destination.inventory(InventorySection.drivers))
                }

                Section("Review") {
                    sidebarRow(.needsAttention)
                    sidebarRow(.intelOnly)
                    ForEach(LocalReviewFilter.navigationCases) { filter in
                        reviewRow(filter)
                    }
                }

                Section("Maintenance") {
                    Label("Cache inspection", systemImage: "internaldrive").tag(Destination.inventory(InventorySection.caches))
                }

                Section("Help") {
                    Label("Tips", systemImage: "lightbulb").tag(Destination.inventory(InventorySection.tips))
                    Button { model.showsHelp = true } label: {
                        Label("User Manual", systemImage: "book.closed")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { model.showsBugReport = true } label: {
                        Label("Report a bug…", systemImage: "ladybug")
                    }.buttonStyle(.plain)
                }


            }
            .listStyle(.sidebar)
            .sheet(isPresented: $showsScanDetails) { ScanScopeView(report: report).environmentObject(model) }
            .padding(.top, StudioUpkeepDesign.Space.small)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Last scan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.scanFailureMessage == nil ? "Scan finished" : "Previous results · rescan failed")
                            .font(.caption.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(report.finishedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        if report.inaccessibleLocationCount > 0 {
                            Text("Some plugin locations weren’t fully scanned.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !model.dawWarnings.isEmpty {
                            Text("The DAW search needs attention.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("View scan details") { showsScanDetails = true }
                            .buttonStyle(.link).font(.caption)
                            .help("See searched locations and why any locations were skipped.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioUpkeepDesign.Space.regular)

            Divider().padding(.horizontal, StudioUpkeepDesign.Space.regular)
            VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developed by").font(.caption).foregroundStyle(.secondary)
                    Text("Mike Konstantinidis")
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Link(destination: URL(string: "https://github.com/mks-devx/MK-Studio-Upkeep")!) {
                    HStack(spacing: 6) {
                        Text("GitHub support").font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.up.right").font(.caption2)
                            .accessibilityHidden(true)
                    }
                }
                .tint(.primary)
                .help("Open project support on GitHub")
                .accessibilityLabel("GitHub support and releases")
                if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                    Text("MK Studio Upkeep · \(version)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioUpkeepDesign.Space.regular)
        }
    }

    private func reviewRow(_ filter: LocalReviewFilter) -> some View {
        let count = model.normalizedProducts.filter { model.matchesReview($0, filter: filter) }.count
        let title = filter.navigationTitle
        let symbol = filter.navigationSymbol
        return HStack(spacing: 10) {
            Label(title, systemImage: symbol).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .tag(Destination.review(filter))
        .help(filter.rawValue)
        .accessibilityLabel("\(title), \(count)")
    }

    private func sidebarRow(_ section: InventorySection) -> some View {
        let count: Int
        if section == .allDAWs {
            count = model.installedDAWs.count
        } else if section == .updatesAvailable {
            count = model.products(in: .updatesAvailable, report: report).count
        } else {
            count = model.products(in: section, report: report).count
        }
        let countLabel = count.formatted()
        let accessibilityCount = count.formatted()

        return HStack(spacing: 10) {
            Label {
                Text(section.rawValue).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: section.symbolName)
            }
            Spacer(minLength: 4)
            Text(countLabel)
                .fixedSize()
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .tag(Destination.inventory(section))
        .accessibilityLabel("\(section.rawValue), \(accessibilityCount)")
    }
}
