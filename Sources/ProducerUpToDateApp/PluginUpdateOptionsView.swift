// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

/// One product's destinations. No version reader or search engine is part of this view.
struct ProductDestinationActions: View {
    let destination: ProductDestination?
    let identifiers: [String]
    @State private var located: VendorAppLocator.Located?
    @State private var failure: String?
    private var manager: ManagerDefinition? { ManagerDefinition.matching(identifiers: identifiers) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { websiteButton; managerButton }
                VStack(alignment: .leading, spacing: 10) { websiteButton; managerButton }
            }
            if destination == nil {
                Text("Official website not identified.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            if let manager, located == nil {
                Text("\(manager.name) isn’t installed or couldn’t be located.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: manager?.id) {
            located = manager.flatMap { VendorAppLocator.locate($0) }
        }
    }
    @ViewBuilder private var websiteButton: some View {
        if let destination {
            Link(destination: destination.url) { Label("Open developer website", systemImage: "arrow.up.right") }
                .buttonStyle(.borderedProminent).tint(.accentColor)
                .help("Check downloads and updates on the developer’s website. " + destination.url.absoluteString)
        }
    }
    @ViewBuilder private var managerButton: some View {
        if let located {
            Button("Open \(located.name)") {
                failure = nil
                VendorAppLocator.open(located.url) { error in
                    Task { @MainActor in failure = error?.localizedDescription }
                }
            }.help("Open the installed manager to check your products. The app’s signature is checked before opening.")
        }
    }
}

struct PluginUpdateOptionsView: View {
    let product: NormalizedPluginProduct
    var body: some View {
        ProductDestinationActions(destination: ProductDestinations.plugin(product),
                                  identifiers: product.bundles.compactMap(\.bundleIdentifier))
    }
}
