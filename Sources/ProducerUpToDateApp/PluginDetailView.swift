// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

struct ProductDetailView: View {
    @EnvironmentObject private var model: AppModel
    let product: NormalizedPluginProduct?
    var update: PluginUpdateResult? = nil
    @AppStorage("showPluginCategories") private var showCategories = true
    @State private var showsIntelHelp = false
    @State private var showsInstalledFiles = true
    @State private var guidanceHost: GuidanceHost = .unspecified
    private let mac = MacArchitecture.current

    var body: some View {
        if let product {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        header(product)
                        productSummary(product)
                        PluginUpdateOptionsView(product: product).id(product.id)
                    }
                    Divider()
                    localFindings(product)
                    DisclosureGroup("Installed files · \(PluginBundleRecord.distinctInstalledCopies(product.bundles).count)", isExpanded: $showsInstalledFiles) {
                        installedCopies(product).padding(.top, 10)
                    }

                    if isIntelOnly(product), mac.processor != .intel {
                        if hasNativeAction(product) { appleSiliconSection(product) }
                        if mac.processor == .appleSilicon {
                            DisclosureGroup("How to use this Intel plugin on Apple Silicon", isExpanded: $showsIntelHelp) {
                                rosettaSection(product).padding(.top, 10)
                            }
                        }
                    }

                    let remainingIssues = product.issues.filter { $0.id != "intel-only" }
                    if !remainingIssues.isEmpty {
                        detailSection("Other local findings") {
                            VStack(spacing: 10) {
                                ForEach(remainingIssues) { issue in IssueView(issue: issue) }
                            }
                        }
                    }

                    TechnicalDetailsDisclosure {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Architectures come from the executable headers. We haven’t loaded or tested the plugin.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let first = product.bundles.first {
                                ProvenanceLine(url: first.path).id(first.path)
                            }
                            if isIntelOnly(product), !hasNativeAction(product) {
                                appleSiliconSection(product)
                            }
                            detailSection("Installed product") {
                                DetailGrid(rows: installedRows(product))
                            }

                            detailSection("Identity match") {
                                VStack(spacing: 0) {
                                    ForEach(product.matchEvidence, id: \.self) { evidence in
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: matchSymbol(evidence.reason))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 18)
                                                .accessibilityHidden(true)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(evidence.reason.rawValue)
                                                    .fontWeight(.medium)
                                                Text(evidence.detail)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(
                                                        horizontal: false,
                                                        vertical: true
                                                    )
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        Divider()
                                    }
                                }
                            }

                            detailSection(
                                product.bundles.count == 1
                                    ? "Installed plugin file"
                                    : "Installed plugin files"
                            ) {
                                VStack(spacing: 10) {
                                    ForEach(product.bundles) { bundle in
                                        BundleDisclosureView(bundle: bundle)
                                    }
                                }
                            }

                        }
                        .padding(.top, 12)
                        if let destination = ProductDestinations.plugin(product) {
                            Text("Developer link reviewed " + destination.reviewedOn).font(.caption).foregroundStyle(.secondary)
                            Text(destination.url.absoluteString).font(.caption).textSelection(.enabled)
                        }
                        ForEach(Array(Set(product.bundles.flatMap { $0.declaredLinks ?? [] })), id: \.self) { link in
                            Link("Address declared by installed software", destination: link.url)
                        }
                    }

                    DisclosureGroup("Uninstall options") {
                        CleanupActionView(
                            plan: CleanupPlanner().plan(for: product),
                            identifiers: product.bundles.compactMap(\.bundleIdentifier)
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
            }

        } else {
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Select a product")
                    .font(.title3.weight(.semibold))
                Text("Choose a product to review its installed files and developer website.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func productSummary(_ product: NormalizedPluginProduct) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(product.bundles.map { InstalledArchitecture.classify($0.architectures) }.allSatisfy { $0 == .universal }
                 ? "Apple Silicon + Intel" : PluginGuidance.intelCopySummary(product) ?? architectureSummary(product))
                .font(.subheadline.weight(.medium))
            if showCategories { Text(product.category.rawValue).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func localFindings(_ product: NormalizedPluginProduct) -> some View {
        if LocalProductReview.cannotRun(product, processor: mac.processor) {
            finding("Some files cannot run on this Mac", detail: "A file is 32-bit only or uses a different processor. Check the developer for a replacement.")
        }
        if PluginGuidance.versionsDiffer(product) {
            finding("Different versions installed", detail: "Your installed copies report different versions. Compare each copy under Installed files.")
        }
        if LocalProductReview.hasRepeatedFormat(product) {
            finding("Multiple copies of one format", detail: "The same plugin format appears in more than one location. Review the files before removing anything.")
        }
        if let related = model.relatedEditions[product.id], !related.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Related editions installed").font(.headline)
                ForEach(related) { other in
                    Button(LocalProductReview.displayName(other.name)) {
                        model.showProduct(other.id)
                    }
                        .buttonStyle(.link)
                }
                Text("Suggested from names and major versions. Older projects may need both editions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if !PluginGuidance.intelOnlyBundles(product).isEmpty, mac.processor == .appleSilicon {
            Text("Intel-only files may need Rosetta or a compatible host. Check the developer for a native installer.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func finding(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func installedCopies(_ product: NormalizedPluginProduct) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let groups = InstalledPluginCopies.groups(for: product)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        FormatBadges(formats: [group.format])
                        Spacer()
                        Text(group.copies.count == 1 ? "1 installed file" : "\(group.copies.count) installed copies")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(group.copies, id: \.path) { bundle in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(InstalledPluginCopies.locationLabel(for: bundle.path)).fontWeight(.medium)
                                Spacer()
                                Text(bundle.displayVersion ?? bundle.buildVersion ?? "Version unknown")
                                    .monospacedDigit().textSelection(.enabled)
                            }
                            Text(bundle.architectureSummary).font(.subheadline).foregroundStyle(.secondary)
                            HStack(alignment: .top) {
                                DisclosureGroup("Location and size") {
                                    Text((bundle.path.path as NSString).abbreviatingWithTildeInPath)
                                        .font(.caption).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                    BundleSizeLine(url: bundle.path).id(bundle.path)
                                }.font(.caption)
                                Spacer(minLength: 8)
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([bundle.path]) }
                                    .controlSize(.small)
                                    .accessibilityLabel("Show \(bundle.format.rawValue) file for \(InstalledPluginCopies.locationLabel(for: bundle.path)) in Finder")
                                    .help(bundle.path.path)
                            }
                        }
                        Divider()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func rosettaSection(_ product: NormalizedPluginProduct) -> some View {
        let facts = IntelOnlyFacts(
            product: product,
            nativeCheck: ProductArchitectureSupportEvaluator.evaluate(product: product, catalogue: model.catalogue?.architectures ?? []),
            rosetta: RosettaStatus.detect())
        return detailSection("Using the Intel version on this Mac") {
            VStack(alignment: .leading, spacing: 12) {
                // Three facts the app can stand behind. Whether the plug-in is stable under Rosetta is not one of them.
                VStack(alignment: .leading, spacing: 6) {
                    Label(facts.files, systemImage: "cpu")
                    Label("Ask the developer whether a native installer exists for this product and format.", systemImage: "arrow.up.circle")
                    Label(facts.rosetta, systemImage: "gearshape.2")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                Text("Rosetta runs Intel code on Apple Silicon. It doesn’t guarantee the plugin behaves.").fontWeight(.semibold)
                Text("First ask the vendor for a native or Universal installer for this exact product and format; we may simply lack the information. If you keep the Intel version, pick your DAW below for instructions.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("DAW you use", selection: $guidanceHost) {
                    ForEach(GuidanceHost.allCases) { host in Text(host.rawValue).tag(host) }
                }
                .onAppear {
                    // Preselect from the DAWs found on this Mac; two supported hosts leave the choice open.
                    if guidanceHost == .unspecified {
                        guidanceHost = GuidanceHost.detected(installedDefinitionIDs: model.installedDAWs.map(\.definitionID))
                    }
                }
                let formats = Set(PluginGuidance.intelOnlyBundles(product).map(\.format))
                if let guidance = RosettaHostGuidance.guidance(host: guidanceHost, formats: formats) {
                    Text(guidance.detail).font(.subheadline).foregroundStyle(.secondary)
                    Link("Open official DAW instructions", destination: guidance.sourceURL)
                    Text("General host guidance · \(guidance.isFresh ? "Reviewed" : "Review expired") \(guidance.reviewedOn). This is not vendor confirmation for this plugin.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if guidanceHost != .unspecified {
                    Text("No reviewed Rosetta guidance for this DAW and installed format. Check the DAW developer and plugin vendor; do not assume another host's rules apply.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                DisclosureGroup("How to check it safely in your DAW") {
                    Text("Use a copy of a project. Confirm the DAW's version and running mode, then load the exact plugin format. Test playback, recording, automation and offline export; save and reopen. Check CPU use, glitches and crashes. A successful load alone does not prove reliable audio or vendor support. After any vendor installation, rescan here to verify the installed architectures.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
                }
            }
        }
    }

    private func appleSiliconSection(_ product: NormalizedPluginProduct) -> some View {
        detailSection("Native installer") {
            Text("This scan checks installed files only. Ask the developer whether a native Apple Silicon installer is available for this product and format.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func hasNativeAction(_ product: NormalizedPluginProduct) -> Bool { false }

    private func isIntelOnly(_ product: NormalizedPluginProduct) -> Bool {
        !PluginGuidance.intelOnlyBundles(product).isEmpty
    }

    private func formatSummary(_ formats: Set<PluginFormat>) -> String {
        formats.map(\.rawValue).sorted().joined(separator: " + ")
    }

    private func header(_ product: NormalizedPluginProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(product.vendor ?? "Unknown vendor")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BrandColor.accent)
            Text(LocalProductReview.displayName(product.name))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.35)
            HStack(spacing: 8) {
                Text(formatSummary(product))
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(installedVersionSummary(product))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func installedRows(
        _ product: NormalizedPluginProduct
    ) -> [DetailGrid.Row] {
        [
            DetailGrid.Row(
                label: "Installed version",
                value: installedVersionSummary(product)
            ),
            DetailGrid.Row(
                label: "Formats",
                value: formatSummary(product)
            ),
            DetailGrid.Row(
                label: "Architectures",
                value: architectureSummary(product)
            ),
            DetailGrid.Row(
                label: "Bundles",
                value: product.bundles.count.formatted()
            ),
            DetailGrid.Row(
                label: "Match confidence",
                value: confidenceLabel(product.confidence)
            )
        ]
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
            return versions.joined(separator: " / ")
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
        if product.architectures.contains(.arm64)
            && product.architectures.contains(.x86_64) {
            return "Apple Silicon + Intel"
        }
        if product.architectures.isEmpty {
            return "Unknown"
        }
        return product.architectures
            .map(\.displayName)
            .sorted()
            .joined(separator: " + ")
    }

    private func confidenceLabel(
        _ confidence: ProductMatchConfidence
    ) -> String {
        switch confidence {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Needs verification"
        }
    }

    private func matchSymbol(_ reason: ProductMatchReason) -> String {
        switch reason {
        case .singleBundle:
            return "shippingbox"
        case .sharedIdentifier:
            return "link"
        case .vendorAndProductName:
            return "text.magnifyingglass"
        case .missingVendorInferred:
            return "questionmark.circle"
        case .multiComponentContainer:
            return "square.stack.3d.up"
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func formattedDate(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        guard let date = parser.date(from: value) else {
            return value
        }
        return date.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
    }
}


/// Lets the user state, locally, which catalogued product a set of unverified files is.
/// Only same-vendor-line records are offered; the catalogue itself is never edited.

/// Signature and copyright of a bundle, read once off the main thread. Static code validation
/// hashes the executable, so it never runs inside a view body.
private struct ProvenanceLine: View {
    let url: URL
    @StateObject private var reading = LatestDetailReading<String>()
    var body: some View {
        Text(reading.value ?? "Checking signature…")
            .font(.caption).foregroundStyle(.secondary)
            .help("Who signed the plugin, verified against Apple’s certificate chain, and its copyright line. Read from the file itself.")
            .task(id: url) {
                let target = url
                await reading.read {
                    let worker = Task.detached(priority: .utility) { BundleProvenance.read(at: target).summary }
                    return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                }
            }
    }
}

/// Size of one installed copy on disk, measured once off the main thread and bounded.
private struct BundleSizeLine: View {
    let url: URL
    @StateObject private var reading = LatestDetailReading<Int64?>()
    var body: some View {
        Text(reading.value.map { "File size: \(BundleFootprint.label($0))" } ?? "Measuring size…")
            .font(.caption).foregroundStyle(.secondary)
            .task(id: url) {
                let target = url
                await reading.read {
                    let worker = Task.detached(priority: .utility) { BundleFootprint.bytes(at: target) }
                    return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                }
            }
    }
}
