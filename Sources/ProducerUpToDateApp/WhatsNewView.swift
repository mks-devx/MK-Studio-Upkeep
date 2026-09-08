// SPDX-License-Identifier: MPL-2.0
import ProducerUpToDateCore
import SwiftUI

struct WhatsNewView: View {
    @EnvironmentObject private var model: AppModel
    let productID: String
    let installed: String
    let available: String

    var body: some View {
        let notes = ReleaseNotesQuery.releases(productID: productID, installed: installed, available: available, notes: model.catalogue?.releaseNotes ?? [])
            .filter { !$0.highlights.isEmpty || $0.importance == .critical }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What’s New").font(.headline)
                Text("\(installed) → \(available)").monospacedDigit()
                Text("Reviewed highlights; the list may not be complete.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(note.version)\(note.releaseDate.map { " · " + $0 } ?? "")").fontWeight(.semibold)
                        if note.importance == .critical {
                            Label("Critical · \(note.criticalReason ?? "Review vendor guidance")", systemImage: "exclamationmark.triangle")
                        }
                        ForEach(note.highlights, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                        Link("Open official source", destination: note.sourceURL)
                    }
                }
            }
        }
    }
}
