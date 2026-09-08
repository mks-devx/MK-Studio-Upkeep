// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

struct InventoryListView: View {
    @EnvironmentObject private var model: AppModel
    let report: ScanReport
    @AppStorage(StudioUpkeepPreference.inventoryDensity)
    private var density = InventoryDensity.comfortable.rawValue
    @AppStorage("showPluginCategories") private var showCategories = true
    @State private var categoryFilter = "All categories"
    @State private var issueFilter = "All issues"

    // Counts include all active filters except the category picker itself.
    private func categoryCandidates(in visible: [NormalizedPluginProduct]) -> [NormalizedPluginProduct] {
        visible.filter { product in
            if model.selectedSection == .needsAttention, issueFilter != "All issues",
               !product.issues.contains(where: { $0.title == issueFilter }) { return false }
            if (model.selectedSection == .allPlugins && model.pluginStatusFilter == .notChecked), issueFilter != "All issues",
               model.pluginResult(product.id)?.notCheckedReason?.rawValue != issueFilter { return false }
            return true
        }
    }

    private var products: [NormalizedPluginProduct] {
        filteredProducts(in: categoryCandidates(in: model.visibleProducts()))
    }

    private func filteredProducts(in candidates: [NormalizedPluginProduct]) -> [NormalizedPluginProduct] {
        candidates.filter { product in
            !showCategories || categoryFilter == "All categories"
                || product.category.rawValue == categoryFilter || product.roleTags.contains(categoryFilter)
        }
    }

    private var rowPadding: CGFloat {
        InventoryDensity(rawValue: density)?.rowPadding
            ?? InventoryDensity.comfortable.rowPadding
    }

    var body: some View {
        let visible = model.visibleProducts()
        let candidates = categoryCandidates(in: visible)
        let counts = PluginCategoryCounts(products: showCategories ? candidates : [])
        let products = filteredProducts(in: candidates)
        return VStack(spacing: 0) {
            if model.selectedSection != .allDAWs {
                InventoryCoverageView(report: report, visibleCount: products.count)
            }
            if model.selectedSection != .allDAWs && model.selectedSection != .updatesAvailable {
                HStack(spacing: 12) {
                    if showCategories {
                        Picker("Category", selection: $categoryFilter) {
                            Text("All categories").tag("All categories")
                            ForEach(PluginCategory.allCases, id: \.rawValue) { category in
                                Text("\(category.rawValue) · \(counts.categories[category, default: 0])")
                                    .tag(category.rawValue)
                            }
                            Divider()
                            ForEach(PluginRoleTags.all, id: \.self) { tag in
                                let count = counts.roles[tag, default: 0]
                                if count > 0 { Text("\(tag) · \(count)").tag(tag) }
                            }
                        }
                        .labelsHidden().frame(width: 230, alignment: .leading)
                        .help("Filter by category. Counts include this view, search and other filters.")
                    }
                    if model.selectedSection == .needsAttention || (model.selectedSection == .allPlugins && model.pluginStatusFilter == .notChecked) {
                        let kinds = model.selectedSection == .needsAttention
                            ? AttentionOrdering.issueKinds(in: visible)
                            : NotCheckedReason.kinds(in: visible.compactMap { model.pluginResult($0.id) })
                        Picker("Issue", selection: $issueFilter) {
                            Text("All issues").tag("All issues")
                            ForEach(kinds, id: \.title) { kind in
                                Text("\(kind.title) · \(kind.count)").tag(kind.title)
                            }
                        }
                        .labelsHidden().frame(width: 230, alignment: .leading)
                        .help("Filter by finding. Results are ordered by severity.")
                    } else if model.selectedSection == .allPlugins {
                        Picker("Architecture", selection: $model.intelOnlyFilter) {
                            Text("All architectures").tag(false)
                            Text("Has Intel-only copies").tag(true)
                        }
                        .labelsHidden().frame(width: 230, alignment: .leading)
                        .help(model.intelOnlyFilter
                              ? "Includes products with at least one Intel-only copy. This does not determine DAW compatibility."
                              : "Includes all detected architectures, including unknown ones. Choose Has Intel-only copies to narrow this view.")
                    }
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            if model.selectedSection == .intelOnly || (model.selectedSection == .allPlugins && model.intelOnlyFilter) || (model.selectedSection == .needsAttention && issueFilter == "Intel-only copy") {
                Text("At least one installed copy is Intel-only; other copies may support Apple Silicon.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider()

            if model.selectedSection == .updatesAvailable {
                UpdateInventoryView()
            } else if model.selectedSection == .allDAWs {
                DAWInventoryView()
            } else if products.isEmpty {
                let hasUserFilters = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.pluginStatusFilter != .allPlugins || model.intelOnlyFilter
                    || (showCategories && categoryFilter != "All categories")
                    || (model.selectedSection == .needsAttention && issueFilter != "All issues")
                if let message = ReviewEmptyMessage.make(for: model.localReviewFilter, hasUserFilters: hasUserFilters) {
                    VStack(spacing: 12) {
                        Text(message.title).font(.title3.weight(.semibold))
                        Text(message.detail).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 440)
                    }
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.localReviewFilter != .all || model.pluginStatusFilter != .allPlugins || model.intelOnlyFilter || (showCategories && categoryFilter != "All categories") || (model.selectedSection == .needsAttention && issueFilter != "All issues") {
                    VStack(spacing: 10) {
                        Text("No plugins match these filters.")
                        Button("Clear filters") { model.localReviewFilter = .all; categoryFilter = "All categories"; issueFilter = "All issues"; model.pluginStatusFilter = .allPlugins; model.intelOnlyFilter = false; model.searchText = "" }.help("Reset filters and search to show all items in this section.")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.searchText.isEmpty {
                    InventoryEmptyView(section: model.selectedSection)
                } else {
                    SearchEmptyView()
                }
            } else {
                Table(products, selection: $model.selectedProductID) {
                    TableColumn("Product") { product in
                        HStack(spacing: 8) {
                            if let severity = product.issues
                                .map(\.severity)
                                .max() {
                                Image(
                                    systemName: severity == .critical
                                        ? "exclamationmark.octagon.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    severity == .critical
                                        ? StudioUpkeepDesign.critical
                                        : StudioUpkeepDesign.warning
                                )
                                .accessibilityHidden(true)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                if showCategories {
                                    Text(([product.category.rawValue] + product.roleTags).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                        .help("Type declared by the plugin itself. Unclear ones stay Uncategorised.")
                                }
                                Text(product.vendor ?? "Unknown vendor")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, rowPadding)
                    }
                    .width(min: 160, ideal: 240)

                    TableColumn("Installed") { product in
                        Text(installedVersionSummary(product))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(
                                product.installedVersions.isEmpty
                                    ? .secondary
                                    : .primary
                            )
                    }
                    .width(min: 80, ideal: 105)

                    TableColumn(model.selectedSection == .needsAttention ? "Needs attention" : (model.selectedSection == .allPlugins && model.pluginStatusFilter == .notChecked) ? "Why not checked" : "Update options") { product in
                        if (model.selectedSection == .allPlugins && model.pluginStatusFilter == .notChecked), let reason = model.pluginResult(product.id)?.notCheckedReason {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reason.rawValue).font(.subheadline)
                                Text(reason.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .help(reason.detail)
                            .accessibilityLabel("Not checked: \(reason.rawValue)")
                        } else if model.selectedSection == .needsAttention {
                            let primary = AttentionOrdering.primaryIssue(of: product)
                            let more = product.issues.count - 1
                            VStack(alignment: .leading, spacing: 2) {
                                Text(primary?.title ?? "Local finding")
                                    .font(.subheadline)
                                    .foregroundStyle(primary?.severity == .critical ? StudioUpkeepDesign.critical : .primary)
                                    .lineLimit(2)
                                if more > 0 {
                                    Text("+\(more) more finding\(more == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .help(primary?.detail ?? "Select the product for details.")
                            .accessibilityLabel("Needs attention: \(primary?.title ?? "local finding")\(more > 0 ? ", plus \(more) more" : "")")
                        } else {
                            Text(ProductDestinations.plugin(product)?.label ?? "Website not identified")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 112, ideal: model.selectedSection == .needsAttention || (model.selectedSection == .allPlugins && model.pluginStatusFilter == .notChecked) ? 260 : 150)

                    TableColumn("Formats") { product in
                        FormatBadges(formats: product.formats)
                    }
                    .width(min: 64, ideal: 82)

                    TableColumn("Architecture") { product in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(architectureSummary(product)).lineLimit(2)
                            if PluginGuidance.intelCopySummary(product) != nil,
                               PluginGuidance.intelOnlyBundles(product).count < product.bundles.count {
                                Text("Intel-only: " + PluginGuidance.intelCopyFormats(product))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .width(min: 100, ideal: 155)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if ids.count == 1, let id = ids.first, let product = model.pluginResult(id)?.product {
                        PluginFinderMenu(bundles: product.bundles)
                        Button("Review uninstall…") { model.cleanupProduct = product }.help("Inspect files and review removal choices. Nothing is removed yet.").disabled(model.isScanning)
                    }
                }
            }
        }
        .onAppear { reconcileSelection() }
        .onChange(of: model.filterResetID) { _ in
            categoryFilter = "All categories"
            issueFilter = "All issues"
        }
        .onChange(of: showCategories) { _ in categoryFilter = "All categories" }
        .onChange(of: model.pluginStatusFilter) { _ in
            issueFilter = "All issues"
            categoryFilter = "All categories"
        }
        .onChange(of: model.localReviewFilter) { _ in categoryFilter = "All categories"; issueFilter = "All issues" }
        .onChange(of: model.intelOnlyFilter) { _ in categoryFilter = "All categories" }
        .onChange(of: model.selectedSection) { _ in
            issueFilter = "All issues"
            reconcileSelection()
        }
        .onChange(of: products.map(\.id)) { _ in reconcileSelection() }
        .onChange(of: model.visibleDAWs().map(\.id)) { _ in reconcileSelection() }
        .onChange(of: model.visibleUpdates().map(\.id)) { _ in reconcileSelection() }
    }

    private func reconcileSelection() {
        if model.selectedSection == .updatesAvailable {
            let rows = model.visibleUpdates()
            if !rows.contains(where: { $0.id == model.selectedUpdateID }) { model.selectedUpdateID = rows.first?.id }
        } else if model.selectedSection == .allDAWs {
            let rows = model.visibleDAWs()
            if !rows.contains(where: { $0.id == model.selectedDAWID }) { model.selectedDAWID = rows.first?.id }
        } else if !products.contains(where: { $0.id == model.selectedProductID }) {
            model.selectedProductID = products.first?.id
        }
    }

    private func installedVersionSummary(
        _ product: NormalizedPluginProduct
    ) -> String {
        let versions = product.installedVersions.sorted()
        switch versions.count {
        case 0:
            return "Unknown"
        case 1:
            return versions[0]
        default:
            return "Multiple"
        }
    }

    private func formatSummary(_ product: NormalizedPluginProduct) -> String {
        product.formats
            .map(\.rawValue)
            .sorted()
            .joined(separator: " + ")
    }

    private func architectureSummary(
        _ product: NormalizedPluginProduct
    ) -> String {
        if let summary = PluginGuidance.intelCopySummary(product) { return summary }
        if product.architectures.contains(.arm64)
            && product.architectures.contains(.x86_64) {
            return "Apple Silicon + Intel"
        }
        if product.architectures == [.arm64] {
            return BinaryArchitecture.arm64.displayName
        }
        if product.architectures == [.x86_64] {
            return BinaryArchitecture.x86_64.displayName
        }
        if product.architectures.isEmpty {
            return "Unknown"
        }
        return product.architectures
            .map(\.displayName)
            .sorted()
            .joined(separator: " + ")
    }
}

/// An empty review is a scan result. Additional user filters need their own reset state.
struct ReviewEmptyMessage: Equatable {
    let title: String
    let detail: String

    static func make(for review: LocalReviewFilter, hasUserFilters: Bool) -> Self? {
        guard !hasUserFilters else { return nil }
        switch review {
        case .all: return nil
        case .cannotRun:
            return .init(title: "No processor incompatibilities found",
                         detail: "No scanned plugin file was identified as unable to run on this processor. Unknown architectures and DAW compatibility remain unchecked.")
        case .differentVersions:
            return .init(title: "No different installed versions found",
                         detail: "No scanned product reports different installed versions. Missing versions remain unknown.")
        case .repeatedCopies:
            return .init(title: "No multiple copies of one format found",
                         detail: "No scanned product has repeated copies of the same format. Files outside the scan are not covered.")
        case .relatedEditions:
            return .init(title: "No related editions identified",
                         detail: "Suggestions use installed names and major versions. Unidentified relationships remain unknown.")
        case .newerEdition:
            return .init(title: "No newer editions identified",
                         detail: "No reviewed newer-edition link matched this inventory. Latest releases are not checked.")
        }
    }
}
