// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

// Components of the product detail view, kept separate so the main view stays readable.

struct BundleDisclosureView: View {
    let bundle: PluginBundleRecord
    @AppStorage(StudioUpkeepPreference.expandTechnicalDetails) private var preferredExpansion = false
    @State private var isExpanded: Bool

    init(bundle: PluginBundleRecord) {
        self.bundle = bundle
        _isExpanded = State(
            initialValue: UserDefaults.standard.bool(
                forKey: "expandTechnicalDetails"
            )
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                DetailGrid(rows: bundleRows)

                if !bundle.identifiers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Identifiers")
                            .font(.subheadline.weight(.semibold))
                        ForEach(bundle.identifiers, id: \.self) { identifier in
                            HStack(alignment: .firstTextBaseline) {
                                Text(identifier.kind.rawValue)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(identifier.value)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }

                if !bundle.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Evidence")
                            .font(.subheadline.weight(.semibold))
                        ForEach(bundle.evidence, id: \.self) { evidence in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(evidence.field)
                                    Text(evidence.kind.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(evidence.value)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }

                Text(bundle.path.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([bundle.path])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bundle.format.rawValue)
                        .fontWeight(.medium)
                    Text(bundle.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(bundle.displayVersion ?? bundle.buildVersion ?? "Unknown")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
        .onChange(of: preferredExpansion) { isExpanded = $0 }
    }

    private var bundleRows: [DetailGrid.Row] {
        [
            DetailGrid.Row(
                label: "Release version",
                value: bundle.displayVersion ?? "Unknown"
            ),
            DetailGrid.Row(
                label: "Build version",
                value: bundle.buildVersion ?? "Unknown"
            ),
            DetailGrid.Row(
                label: "Architecture",
                value: bundle.architectureSummary
            ),
            DetailGrid.Row(
                label: "Bundle identifier",
                value: bundle.bundleIdentifier ?? "Unknown"
            )
        ]
    }
}

struct IssueView: View {
    let issue: ScanIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName: issue.severity == .critical
                    ? "exclamationmark.octagon.fill"
                    : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(
                issue.severity == .critical
                    ? StudioUpkeepDesign.critical
                    : StudioUpkeepDesign.warning
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .fontWeight(.semibold)
                Text(issue.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
    }
}

struct DetailGrid: View {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    let rows: [Row]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .textSelection(.enabled)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }
}

struct IdentityConfirmationView: View {
    @EnvironmentObject private var model: AppModel
    let product: NormalizedPluginProduct
    let result: PluginUpdateResult
    @State private var selection: String = ""

    var body: some View {
        let candidates = model.identityCandidates(for: product)
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm identity").font(.headline)
            if result.identityConfirmedByUser, let id = model.identityConfirmations.catalogueID(for: product.id) {
                Text("You confirmed these files as “\(candidates.first { $0.catalogueID == id }?.productAliases.first ?? id)”. The comparison above rests on that choice, stored on this Mac only.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Remove confirmation") { model.removeIdentityConfirmation(of: product) }
            } else if candidates.isEmpty {
                Text("No catalogued product comes from this vendor yet, so there is nothing to confirm. The files stay listed with their local details.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("We couldn’t tie these files to one product. If you know which catalogued product they are, choose it below. Only products from the same vendor are offered. Your choice stays on this Mac and is marked as confirmed by you.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Picker("Catalogued product", selection: $selection) {
                        Text("Choose…").tag("")
                        ForEach(candidates, id: \.catalogueID) { record in
                            Text("\(record.productAliases.first ?? record.catalogueID) · \(record.latestVersion)").tag(record.catalogueID)
                        }
                    }.frame(maxWidth: 320)
                    Button("Use this entry") {
                        if let record = candidates.first(where: { $0.catalogueID == selection }) { model.confirmIdentity(of: product, as: record) }
                    }.disabled(selection.isEmpty)
                }
            }
        }
    }
}
