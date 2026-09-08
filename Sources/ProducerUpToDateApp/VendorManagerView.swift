// SPDX-License-Identifier: MPL-2.0
import AppKit
import ProducerUpToDateCore
import SwiftUI

struct VendorManagerView: View {
    let identifiers: [String]
    @State private var failure: String?

    var body: some View {
        if let manager = VendorManager.matching(identifiers: identifiers) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vendor app").font(.headline)
                Text("Suggested from the product’s identity; it may not be how you installed it.")
                    .font(.caption).foregroundStyle(.secondary)
                if let located = VendorAppLocator.locate(bundleIdentifier: nil, appName: manager.name) {
                    Button("Open \(manager.name)") {
                        VendorAppLocator.open(located.url) { error in
                            Task { @MainActor in failure = error?.localizedDescription }
                        }
                    }
                } else {
                    Text("\(manager.name) was not found on this Mac.").foregroundStyle(.secondary)
                    Link("Get \(manager.name)", destination: manager.officialURL)
                }
                Text(manager.uninstallDetail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Official uninstall guidance", destination: manager.uninstallURL)
                if let failure { Text(failure).foregroundStyle(.secondary) }
            }
        }
    }
}
