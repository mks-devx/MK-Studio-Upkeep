// SPDX-License-Identifier: BUSL-1.1
import OfficialUpdateSupport
import SwiftUI

struct OfficialUpdatesView: View {
    @ObservedObject var session: OfficialUpdateSession
    var productID: String? = nil
    private var visibleTargets: [OfficialTarget] {
        session.targets.filter { productID == nil || $0.productID == productID }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Text("Automatic update detection").font(.headline)
                if productID == nil {
                    Text("Supported: \(session.eligibleProductCount) of \(session.productCount) products · \(session.eligibleCount) of \(session.targets.count) installed copies.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Toggle("Allow official-source checks this session", isOn: $session.optedIn)
                    .toggleStyle(.checkbox)
                Text("Like any website visit, the site sees your IP address; your inventory stays on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if !session.hosts.isEmpty {
                    Text("Sources: " + session.hosts).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Button(session.isChecking ? "Checking…" : "Check supported products") { session.check() }
                        .disabled(!session.optedIn || session.isChecking || session.eligibleCount == 0 || context.date < session.nextCheckAt)
                    if session.isChecking {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { session.invalidateResults() }
                    }
                }
                if !session.isChecking && context.date < session.nextCheckAt {
                    Text("You can check again in a minute.").font(.caption).foregroundStyle(.secondary)
                }
                if let message = session.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if productID == nil {
                    let compared = session.observations.filter { [.update, .matched, .ahead].contains($0.state(at: context.date)) }
                    let updates = compared.filter { $0.state(at: context.date) == .update }
                    Text("Compared \(compared.count) of \(session.targets.count) copies · \(updates.count) with confirmed updates.")
                        .font(.subheadline)
                    Text("Results expire after 24 hours. Select a product for its source, check time and individual copies.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !session.observations.isEmpty {
                        DisclosureGroup("Results for supported copies") { results(at: context.date, supportedOnly: true) }
                    }
                } else {
                    results(at: context.date, supportedOnly: false)
                }
                Text("Release versions only. Check system requirements and your licence on the official page before installing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private func results(at date: Date, supportedOnly: Bool) -> some View {
        ForEach(visibleTargets.filter { !supportedOnly || $0.entry != nil }) { target in
            VStack(alignment: .leading, spacing: 5) {
                Text(target.label).font(.subheadline.weight(.medium))
                Text("Installed: " + (target.installed ?? "Unknown")).font(.caption).foregroundStyle(.secondary)
                if let observation = session.observations.first(where: { $0.copyID == target.id }) {
                    Text(observation.state(at: date).rawValue).font(.subheadline)
                    if let latest = observation.latest {
                        Text("Release at last check: " + latest).font(.caption)
                    }
                    if let failure = observation.failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
                    Text("Checked " + observation.checkedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(target.reason ?? "Not checked online.").font(.caption).foregroundStyle(.secondary)
                }
                if let entry = target.entry {
                    Link("Official source", destination: entry.source)
                    Text(entry.source.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let successorID = entry.successor,
                       let successor = session.directory?.entries.first(where: { $0.id == successorID }) {
                        Text("Newer edition: \(successor.name). This is separate from updates to your edition and may cost extra.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("About the newer edition", destination: successor.provenance)
                    }
                }
                // Local path disambiguates multiple copies; never enters a request.
                DisclosureGroup("Installed location") {
                    Text(target.path.path).font(.caption).textSelection(.enabled)
                }
            }.padding(.vertical, 6)
        }
    }
}

struct OfficialUpdateRow: View {
    @ObservedObject var session: OfficialUpdateSession
    let productID: String
    let fallback: String
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(session.rowLabel(productID: productID, now: context.date) ?? fallback)
                .font(.subheadline).foregroundStyle(.secondary)
                .help("Select the product for individual copies, source and check time.")
        }
    }
}
