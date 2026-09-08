// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct OnboardingView: View {
    var title = "Set up your first scan"
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var complete = false
    @AppStorage(StudioUpkeepPreference.scanAudioUnits) private var au = true
    @AppStorage(StudioUpkeepPreference.scanVST3) private var vst3 = true
    @AppStorage(StudioUpkeepPreference.scanVST2) private var vst2 = true
    @AppStorage(StudioUpkeepPreference.scanCLAP) private var clap = true
    @AppStorage(StudioUpkeepPreference.scanDAWs) private var daws = true
    @AppStorage(StudioUpkeepPreference.expandTechnicalDetails) private var technical = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.weight(.semibold))
            Text("No tracking. Your scan data stays on your Mac.")
                .foregroundStyle(.secondary)
            Text("Scanning reads installed versions and processor architecture on this Mac. Developer links open your browser; software managers open only when you choose them. Your inventory, file paths and activity readings stay local.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Free for personal and professional studio use. Report problems on GitHub after removing personal information.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Audio Units", isOn: $au)
                    Toggle("VST3", isOn: $vst3)
                    Toggle("VST2", isOn: $vst2)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("CLAP", isOn: $clap)
                    Toggle("DAW applications", isOn: $daws)
                    Toggle("Expand technical details", isOn: $technical)
                }
            }
            Text("Plugins in the system and user Library › Audio › Plug-Ins folders, and DAWs in both Applications folders. You can add folders later in Settings.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Select a product after scanning to see its update options. Check current releases through the developer’s app or website. Scanning does not check for updates. Hardware and drivers have their own section.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }.help("Stop this operation or close this view.").keyboardShortcut(.cancelAction)
                Spacer()
                Button("Scan This Mac") { complete = true; dismiss(); model.startScan() }.help("Find installed audio software without loading or changing it.")
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!(au || vst3 || vst2 || clap || daws))
            }
        }.padding(28).frame(width: 640)
    }
}

struct StudioMenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("MK Studio Upkeep")
        Text(model.menuBarStatus)
        Divider()
        Button("Open MK Studio Upkeep") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if model.isScanning {
            Button("Cancel Scan") { model.cancelScan() }
        } else {
            Button("Scan This Mac") { model.startScan() }.help("Find installed audio software without loading or changing it.")
        }
        Button("Quit MK Studio Upkeep") { NSApp.terminate(nil) }
        .onAppear { model.refreshEvidence() }
    }
}
