// SPDX-License-Identifier: BUSL-1.1
import ProducerUpToDateCore
import SwiftUI

/// What changed since the previous scan on this Mac: names and versions only.
struct ScanChangesView: View {
    let changes: ScanComparison

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var content: some View {

            VStack(alignment: .leading, spacing: 14) {
                Text("Since the scan on \(changes.previousFinishedAt.formatted(date: .abbreviated, time: .shortened))").font(.headline)
                group("Appeared", changes.added, systemImage: "plus.circle") { "\($0.entry.name) · \($0.entry.version)" }
                group("Disappeared", changes.removed, systemImage: "minus.circle") { "\($0.entry.name) · \($0.entry.version)" }
                group("Changed version", changes.changed, systemImage: "arrow.triangle.2.circlepath") { "\($0.entry.name) · \($0.previousVersion ?? "?") → \($0.entry.version)" }
            }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [ScanComparison.Change], systemImage: String, line: @escaping (ScanComparison.Change) -> String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(title) · \(items.count)", systemImage: systemImage).font(.subheadline.weight(.semibold))
                ForEach(items) { change in
                    Text(line(change)).font(.caption).textSelection(.enabled)
                    if !change.entry.vendor.isEmpty { Text(change.entry.vendor).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
