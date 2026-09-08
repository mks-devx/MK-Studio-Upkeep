// SPDX-License-Identifier: MPL-2.0
import ProducerUpToDateCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(StudioUpkeepPreference.scanOnLaunch)
    private var scanOnLaunch = false
    @State private var handledAutomaticScan = false
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            // Keep the same split-view identity while a rescan retains its previous report.
            // Separate scanning/complete branches recreate the AppKit-backed columns.
            if let report = model.currentReport {
                InventoryShell(report: report, showsScanProgress: model.isScanning)
            } else {
                switch model.scanState {
                case .ready:
                    WelcomeView()
                case let .scanning(startedAt, _):
                    ScanningView(startedAt: startedAt)
                case let .failed(message):
                    ScanFailureView(message: message)
                case .complete:
                    WelcomeView() // A complete report is handled above.
                }
            }
        }
        .sheet(isPresented: $model.showsHelp) {
            StudioUpkeepHelpView()
        }
        .sheet(isPresented: $model.showsBugReport) { BugReportView() }
        .sheet(item: $model.cleanupProduct) { product in
            CleanupActionView(plan: CleanupPlanner().plan(for: product),
                identifiers: product.bundles.compactMap(\.bundleIdentifier), reviewOnly: true)
        }
        .sheet(item: $model.cleanupDAW) { daw in
            CleanupActionView(plan: CleanupPlanner().plan(for: daw),
                identifiers: [daw.bundleIdentifier].compactMap { $0 }, reviewOnly: true)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.refreshEvidence() }
        }
        .task {
            guard !handledAutomaticScan else {
                return
            }
            handledAutomaticScan = true
            if onboardingComplete && scanOnLaunch && model.currentReport == nil && !model.isScanning {
                model.startScan()
            }
        }
        .studioCanvasBackground()
    }
}

private struct InventoryShell: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport
    let showsScanProgress: Bool
    @AppStorage(StudioUpkeepPreference.sidebarPosition) private var sidebarPosition = "left"
    @State private var tipsSearch = ""
    @StateObject private var caches = CacheBrowser()
    @StateObject private var hardware = HardwareBrowser()
    @StateObject private var drivers = HardwareBrowser(driversOnly: true)
    @StateObject private var managers = ManagerBrowser()

    var body: some View {
        GeometryReader { geometry in
            splitView
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private var splitView: some View {
        Group {
            if sidebarPosition == "top" {
                VStack(spacing: 0) {
                    TopNavigationView()
                    Divider()
                    HSplitView {
                        inventoryColumn.frame(minWidth: 540, maxWidth: .infinity)
                        detailColumn.frame(minWidth: 360, idealWidth: 440, maxWidth: 600)
                    }
                }
            } else if sidebarPosition == "right" {
                HSplitView {
                    detailColumn.frame(minWidth: 360, idealWidth: 440, maxWidth: 600)
                    inventoryColumn.frame(minWidth: 540, maxWidth: .infinity)
                    sidebarColumn.frame(minWidth: 210, idealWidth: 230, maxWidth: 270)
                }
            } else {
                NavigationSplitView {
                    sidebarColumn
                } content: {
                    inventoryColumn
                } detail: {
                    detailColumn
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
            // The title lives on this stable container: switching sections changes its text, never the
            // toolbar's shape. Title and toolbar background stay visible, so content never slides under them.
            .navigationTitle(model.inventoryTitle)
            .toolbarBackground(.visible, for: .windowToolbar)
            // The window owns search; the inventory owns its action bar. A titlebar
            // item is not clipped to a split column and can straddle its divider.
            .searchable(text: searchText, placement: .toolbar, prompt: searchPrompt)


    }

    private var sidebarColumn: some View {

            BoundedColumn { SidebarView(report: report) }
                .navigationSplitViewColumnWidth(
                    min: 210,
                    ideal: 230,
                    max: 270
                )

    }
    private var inventoryColumn: some View {

            BoundedColumn {
            VStack(spacing: 0) {
                if showsScanProgress {
                    RescanProgressView()
                    Divider()
                }
                if let failure = model.scanFailureMessage {
                    HStack(alignment: .top, spacing: 12) {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("Retry scan") { model.startScan() }.disabled(model.isScanning)
                    }
                    .padding(12)
                    Divider()
                }
                if model.selectedSection == .caches {
                    CacheInspectionView(browser: caches)
                } else if model.selectedSection == .tips {
                    StudioTipsView(search: tipsSearch)
                } else if model.selectedSection == .overview {
                    OverviewView(report: report)
                } else if model.selectedSection == .hardware {
                    HardwareView(browser: hardware).id(InventorySection.hardware)
                } else if model.selectedSection == .drivers {
                    HardwareView(browser: drivers).id(InventorySection.drivers)
                } else if model.selectedSection == .managers {
                    ManagersView(browser: managers)
                } else {
                    InventoryListView(report: report)
                        // DAW and plugin Tables have different columns. Never recycle an
                        // AppKit table across those section layouts.
                        .id(model.selectedSection)
                }
            }
            }
            .navigationSplitViewColumnWidth(
                min: 540,
                ideal: 700
            )

    }
    private var detailColumn: some View {

            BoundedColumn {
            Group {
                if model.selectedSection == .caches {
                    CacheInspectionContextView()
                } else if model.selectedSection == .tips {
                    StudioTipsContextView()
                } else if model.selectedSection == .overview {
                    OverviewDetailView(report: report)
                } else if model.selectedSection == .hardware {
                    HardwareDetailView(browser: hardware).id(InventorySection.hardware)
                } else if model.selectedSection == .drivers {
                    HardwareDetailView(browser: drivers).id(InventorySection.drivers)
                } else if model.selectedSection == .managers {
                    ManagerDetailView(browser: managers)
                } else if model.selectedSection == .updatesAvailable {
                    if let update = model.selectedPluginUpdate() {
                        ProductDetailView(
                            product: update.product,
                            update: update
                        )
                    } else {
                        DAWDetailView(daw: model.selectedUpdateDAW())
                    }
                } else if model.selectedSection == .allDAWs {
                    DAWDetailView(
                        daw: model.daw(withID: model.selectedDAWID)
                    ).id(model.selectedDAWID)
                } else {
                    ProductDetailView(
                        product: model.product(withID: model.selectedProductID)
                    ).id(model.selectedProductID)
                }
            }
            }
                .navigationSplitViewColumnWidth(
                    min: 360,
                    ideal: 440,
                    max: 600
                )

    }

    private var searchText: Binding<String> {
        switch model.selectedSection {
        case .caches: return $caches.search
        case .tips: return $tipsSearch
        case .hardware: return $hardware.search
        case .drivers: return $drivers.search
        case .managers: return $managers.search
        case .overview: return Binding(get: { "" }, set: { value in
            guard !value.isEmpty else { return }
            model.searchText = value
            model.pluginStatusFilter = .allPlugins
            model.intelOnlyFilter = false
            model.selectedSection = .allPlugins
        })
        default: return $model.searchText
        }
    }

    private var searchPrompt: String {
        switch model.selectedSection {
        case .caches: return "Search cache locations"
        case .tips: return "Search tips"
        case .hardware: return "Search hardware"
        case .drivers: return "Search drivers"
        case .managers: return "Search managers"
        case .updatesAvailable: return "Search updates"
        case .allDAWs: return "Search DAWs"
        default: return "Search plugins"
        }
    }
}

/// AppKit-backed table fitting sizes must not determine the height of the window.
private struct BoundedColumn<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        GeometryReader { geometry in
            content
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}

private struct RescanProgressView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Rescanning plugins and DAWs…")
                .fontWeight(.medium)
            Spacer()
            Button("Cancel Scan") {
                model.cancelScan()
            }
            .buttonStyle(.borderless)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
