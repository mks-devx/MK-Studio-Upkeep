// SPDX-License-Identifier: MPL-2.0
import AppKit
import ProducerUpToDateCore
import SwiftUI

/// Finder may foreground only one folder when passed files from several locations.
/// Reveal one explicitly chosen copy instead; keep same-format duplicates distinct.
struct PluginFinderMenu: View {
    let bundles: [PluginBundleRecord]
    var body: some View {
        let copies = PluginBundleRecord.distinctInstalledCopies(bundles)
        if copies.count == 1, let copy = copies.first {
            Button("Show in Finder") { reveal(copy.path) }.help("Reveal this location in Finder. Nothing is removed.")
        } else if !copies.isEmpty {
            Menu("Show in Finder") {
                ForEach(copies, id: \.path) { copy in
                    Button("\(copy.format.rawValue) — \((copy.path.path as NSString).abbreviatingWithTildeInPath)") {
                        reveal(copy.path)
                    }
                }
            }
        }
    }
    private func reveal(_ path: URL) { NSWorkspace.shared.activateFileViewerSelecting([path]) }
}
