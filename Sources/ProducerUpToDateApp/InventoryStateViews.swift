// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

struct InventoryEmptyView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(StudioUpkeepPreference.scanDAWs) private var scansDAWs = true
    let section: InventorySection

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: emptySymbol)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var emptySymbol: String {
        switch section {
        case .overview, .tips, .caches:
            return section.symbolName
        case .needsAttention:
            return "checkmark.circle"
        case .updatesAvailable:
            return "arrow.down.circle"
        case .upToDate, .managedElsewhere:
            return section.symbolName
        case .notChecked, .intelOnly:
            return "checkmark.circle"
        case .allPlugins:
            return "waveform.slash"
        case .hardware, .drivers, .managers: return section.symbolName
        case .allDAWs:
            return "slider.horizontal.3"
        }
    }

    private var title: String {
        switch section {
        case .overview, .tips, .caches:
            return "No scan yet"
        case .needsAttention:
            return "No local problems found"
        case .updatesAvailable:
            return "Latest releases are not checked"
        case .upToDate:
            return "Latest releases are not checked"
        case .managedElsewhere:
            return "No product is managed by a vendor app"
        case .notChecked:
            return "No products in this view"
        case .intelOnly:
            return "No Intel-only copies found"
        case .allPlugins:
            return model.currentReport?.locations.isEmpty == true ? "No plugin formats selected" : "No plugins found in this scan"
        case .hardware, .drivers, .managers: return "No items found"
        case .allDAWs:
            return scansDAWs ? "No DAWs found in this scan" : "DAW scanning is turned off"
        }
    }

    private var detail: String {
        switch section {
        case .overview, .tips, .caches:
            return "Scan this Mac to fill the overview."
        case .needsAttention:
            return "Local findings only. Compatibility with your DAW isn’t checked here."
        case .updatesAvailable:
            return "Select a product in Plugins to open its developer website or installed software manager."
        case .upToDate:
            return "Scanning reads installed files. Check current releases with the developer."
        case .managedElsewhere:
            return "Products whose updates arrive through a vendor app such as Native Access appear here."
        case .intelOnly:
            return "No scanned file was identified as Intel-only. Unknown architectures remain unknown; host compatibility is not checked."
        case .notChecked:
            return "Choose Plugins to review installed products and their developer links."
        case .allPlugins:
            return "Review enabled formats and plugin folders in Settings → Scanning, then rescan. Scan details list the searched locations and any access problems."
        case .hardware, .drivers, .managers: return "Refresh this inventory to check installed items."
        case .allDAWs:
            return scansDAWs ? "No recognised DAW was found in the searched application folders. Review Scan details for the search scope and any access problems." : "Enable DAW applications in Settings → Scanning, then rescan."
        }
    }
}

struct SearchEmptyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("No matching results")
                    .font(.title3.weight(.semibold))
                Text("Try a different product, vendor, format, or version.")
                    .foregroundStyle(.secondary)
            }
            Button("Clear Search") {
                model.searchText = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
