// SPDX-License-Identifier: BUSL-1.1
import AppKit
import Combine
import Foundation
import ProducerUpToDateCore

/// Section, search and selection helpers over the scan results.
extension AppModel {
    /// Every navigation surface opens the same unfiltered destination.
    func navigate(to section: InventorySection) {
        searchText = ""
        pluginStatusFilter = .allPlugins
        intelOnlyFilter = false
        dawStatusFilter = "All DAWs"
        selectedSection = section
        resetLocalFilters()
    }

    func navigate(to review: LocalReviewFilter) {
        navigate(to: InventorySection.allPlugins)
        localReviewFilter = review
    }

    func showProduct(_ id: String) {
        navigate(to: InventorySection.allPlugins)
        selectedProductID = id
    }

    func showDAW(_ id: String) {
        navigate(to: InventorySection.allDAWs)
        selectedDAWID = id
    }

    func products(
        in section: InventorySection,
        report: ScanReport? = nil
    ) -> [NormalizedPluginProduct] {
        guard (report ?? currentReport) != nil else { return [] }
        let products = normalizedProducts

        switch section {
        case .overview, .tips, .caches:
            return []
        case .needsAttention:
            return AttentionOrdering.ordered(products.filter { !$0.issues.isEmpty })
        case .updatesAvailable:
            return products.filter { pluginResultsByID[$0.id]?.updateState == .updateAvailable }
        case .upToDate:
            return products.filter { pluginResultsByID[$0.id]?.updateState == .current }
        case .managedElsewhere:
            return products.filter { product in
                guard let result = pluginResultsByID[product.id], result.latestVersion == nil else { return false }
                if case .manager = result.route { return true }
                return false
            }
        case .intelOnly:
            return products.filter { !PluginGuidance.intelOnlyBundles($0).isEmpty }
        case .notChecked:
            // Same set the coverage popover calls unverified: no comparison, and no vendor app that owns the updates.
            return products.filter { product in
                guard let result = pluginResultsByID[product.id], result.latestVersion == nil else { return false }
                if case .manager = result.route { return false }
                return true
            }
        case .allPlugins:
            return products
        case .allDAWs, .hardware, .drivers, .managers:
            return []
        }
    }

    var inventoryTitle: String {
        guard selectedSection == .allPlugins else { return selectedSection.rawValue }
        if localReviewFilter != .all { return localReviewFilter.rawValue }
        return intelOnlyFilter ? InventorySection.intelOnly.rawValue : InventorySection.allPlugins.rawValue
    }

    func matchesReview(_ product: NormalizedPluginProduct, filter: LocalReviewFilter) -> Bool {
            switch filter {
            case .all: return true
            case .cannotRun: return LocalProductReview.cannotRun(product, processor: MacArchitecture.current.processor)
            case .differentVersions: return PluginGuidance.versionsDiffer(product)
            case .repeatedCopies: return LocalProductReview.hasRepeatedFormat(product)
            case .relatedEditions: return relatedEditions[product.id] != nil
            }
    }

    func visibleProducts() -> [NormalizedPluginProduct] {
        let sectionProducts = products(in: selectedSection == .allPlugins ? pluginStatusFilter : selectedSection)
            .filter { selectedSection != .allPlugins || !intelOnlyFilter || !PluginGuidance.intelOnlyBundles($0).isEmpty }
        let reviewedProducts = sectionProducts.filter { matchesReview($0, filter: localReviewFilter) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return reviewedProducts
        }

        return reviewedProducts.filter { product in
            let productValues = [
                product.name,
                product.vendor
            ].compactMap { $0 }
            let bundleValues: [String] = product.bundles.flatMap { bundle in
                let values: [String?] = [
                    bundle.name,
                    bundle.vendor,
                    bundle.bundleIdentifier,
                    bundle.displayVersion,
                    bundle.buildVersion,
                    bundle.format.rawValue,
                    bundle.path.path
                ]
                return values.compactMap { $0 }
            }

            return (productValues + bundleValues).contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func product(withID id: String?) -> NormalizedPluginProduct? {
        guard let id else {
            return nil
        }
        return products(in: .allPlugins).first { $0.id == id }
    }

    func visibleDAWs() -> [InstalledDAWRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = installedDAWs.filter { daw in
            switch dawStatusFilter {
            case "Updates available": return daw.updateState == .updateAvailable
            case "Matches listed version": return daw.updateState == .current
            case "Not verified": return daw.updateState != .current && daw.updateState != .updateAvailable
            default: return true
            }
        }
        guard !query.isEmpty else { return candidates }
        return candidates.filter { daw in
            [
                daw.name,
                daw.vendor,
                daw.bundleIdentifier,
                daw.installedVersion,
                daw.path.path
            ].compactMap { $0 }.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    func visibleDAWUpdates() -> [InstalledDAWRecord] {
        visibleDAWs().filter { $0.updateState == .updateAvailable }
    }

    func visibleUpdates() -> [SoftwareUpdateItem] {
        let pluginItems = pluginUpdateResults
            .filter { $0.updateState == .updateAvailable }
            .map(SoftwareUpdateItem.init)
        let dawItems = installedDAWs
            .filter { $0.updateState == .updateAvailable }
            .map(SoftwareUpdateItem.init)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updates = (pluginItems + dawItems).sorted {
            let vendorComparison = $0.vendor.localizedStandardCompare($1.vendor)
            if vendorComparison != .orderedSame {
                return vendorComparison == .orderedAscending
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard !query.isEmpty else {
            return updates
        }
        return updates.filter {
            [$0.name, $0.vendor, $0.installedVersion, $0.latestVersion]
                .contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
        }
    }

    var updateCount: Int {
        pluginUpdateResults.filter {
            $0.updateState == .updateAvailable
        }.count + installedDAWs.filter {
            $0.updateState == .updateAvailable
        }.count
    }

    func selectedPluginUpdate() -> PluginUpdateResult? {
        guard let selectedUpdateID,
              selectedUpdateID.hasPrefix("plugin:")
        else {
            return nil
        }
        let id = String(selectedUpdateID.dropFirst("plugin:".count))
        return pluginUpdateResults.first { $0.id == id }
    }

    func selectedUpdateDAW() -> InstalledDAWRecord? {
        guard let selectedUpdateID,
              selectedUpdateID.hasPrefix("daw:")
        else {
            return nil
        }
        let id = String(selectedUpdateID.dropFirst("daw:".count))
        return installedDAWs.first { $0.id == id }
    }

    func daw(withID id: String?) -> InstalledDAWRecord? {
        guard let id else {
            return nil
        }
        return installedDAWs.first { $0.id == id }
    }
}
