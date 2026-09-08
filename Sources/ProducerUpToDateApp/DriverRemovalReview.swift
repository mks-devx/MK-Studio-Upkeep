// SPDX-License-Identifier: MPL-2.0
import AppKit
import ProducerUpToDateCore
import SwiftUI

struct DriverRemovalReview: View {
    let driver: DriverRecord
    var protection: RemovalProtection = .none
    @Environment(\.dismiss) private var dismiss
    @State private var report: UninstallDiscoveryReport?
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review driver removal · \(driver.name)").font(.title2)
            if protection.isRed, let reason = protection.reason { DoNotDeleteBanner(reason: reason) }
            Text(DriverDescription.describe(driver)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Removing a shared or active driver can silence audio and other devices. An unplugged device doesn’t mean its driver is unused.", systemImage: "exclamationmark.triangle")
            Text(driver.path.path).font(.caption).textSelection(.enabled)
            Text("Nothing is deleted here. Drivers and system extensions need the maker’s removal procedure, often with an administrator password and a restart.")
            VendorManagerView(identifiers: [driver.bundleIdentifier].compactMap { $0 })
            if VendorManager.matching(identifiers: [driver.bundleIdentifier].compactMap { $0 }) == nil {
                Text("No reviewed removal procedure for this driver. Ask its maker before changing files.")
            }
            if let report {
                List {
                    Section("Associated files · preserved") {
                        ForEach(report.findings) { item in
                            VStack(alignment: .leading) {
                                Text(item.path.path).font(.caption).textSelection(.enabled)
                                Text(item.evidence).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if report.findings.isEmpty { Text("No exact bundle-identifier filename matches found.") }
                    }
                    Section("Limits") {
                        Text("Common system and user Library support locations only; hidden entries included. No whole-disk or exclusive-ownership guarantee.")
                        ForEach(report.warnings, id: \.self) { Text($0) }
                    }
                }
            } else if let failure { Text(failure) }
            else { ProgressView("Searching associated files…") }
            HStack {
                Button("Show driver in Finder") { NSWorkspace.shared.activateFileViewerSelecting([driver.path]) }
                Spacer()
                Button("Done") { dismiss() }.help("Close this view.")
            }
        }.padding(24).frame(width: 760, height: 650)
        .task {
            let identifiers = [driver.bundleIdentifier].compactMap { $0 }
            let worker = Task.detached { try UninstallDiscovery.scan(identifiers: identifiers) }
            do {
                let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                report = value
            } catch is CancellationError { }
            catch { failure = error.localizedDescription }
        }
    }
}
