// SPDX-License-Identifier: BUSL-1.1
import AppKit
import ProducerUpToDateCore
import SwiftUI

struct DAWDetailView: View {
    @EnvironmentObject private var model: AppModel
    let daw: InstalledDAWRecord?
    var body: some View {
        if let daw {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(daw.vendor).font(.subheadline).foregroundStyle(.secondary)
                        Text(LocalProductReview.displayName(daw.name)).font(.system(size: 28, weight: .semibold))
                        Text("Version " + (daw.conciseInstalledVersion ?? "unknown")).font(.subheadline).foregroundStyle(.secondary)
                        Text(daw.architectureSummary).font(.subheadline.weight(.medium))
                    }
                    if daw.identityIsInferred {
                        Text("Recognised by name only. Its official website could not be confirmed.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let store = DAWUpdateSource.appStoreDestination(for: daw) {
                        Button("Open App Store Updates") { NSWorkspace.shared.open(store.updates) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        ProductDestinationActions(destination: ProductDestinations.daw(daw), identifiers: [daw.bundleIdentifier].compactMap { $0 })
                    }
                    let architecture = InstalledArchitecture.classify(daw.architectures)
                    if architecture == .legacy32 {
                        Text("This 32-bit application cannot run on current macOS. Check the developer for a replacement.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if architecture == .intel64 && MacArchitecture.current.processor == .appleSilicon {
                        Text("Intel-only. It may run through Rosetta; check the developer’s macOS requirements.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if architecture == .appleSilicon && MacArchitecture.current.processor == .intel {
                        Text("This application requires Apple Silicon and cannot run on an Intel Mac.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    let others = model.installedDAWs.filter { $0.definitionID == daw.definitionID && $0.id != daw.id }
                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other installations").font(.headline)
                            ForEach(others) { other in
                                Button("\(other.name) · \(other.installedVersion ?? "Unknown version")") { model.showDAW(other.id) }
                                    .buttonStyle(.link)
                            }
                            Text("Different editions may be needed by existing projects.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("Installed application") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(daw.path.path).font(.caption).textSelection(.enabled)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([daw.path]) }
                        }.padding(.top, 10)
                    }
                    TechnicalDetailsDisclosure {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bundle identifier: " + (daw.bundleIdentifier ?? "Unknown"))
                            Text("Release version: " + (daw.displayVersion ?? "Unknown"))
                            Text("Build: " + (daw.buildVersion ?? "Unknown"))
                            Text("Architecture: " + daw.architectureSummary)
                            if let destination = ProductDestinations.daw(daw) {
                                Text(destination.url.absoluteString).textSelection(.enabled)
                            }
                            Text("Architecture is read from the installed file. DAW behaviour and vendor support have not been tested.")
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 10)
                    }
                    DisclosureGroup("Uninstall options") {
                        CleanupActionView(plan: CleanupPlanner().plan(for: daw), identifiers: [daw.bundleIdentifier].compactMap { $0 })
                            .padding(.top, 10)
                    }
                }.padding(24).frame(maxWidth: 640, alignment: .leading)
            }
        } else {
            Text("Select a DAW to see its installed version and options.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
