// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct StudioTip: Identifiable {
    let id: String
    let title: String
    let scope: String
    let text: String
    let source: String
    let url: String

    static let all: [StudioTip] = [
        .init(id: "recording", title: "Before recording", scope: "Session preparation · our recommendation",
              text: "Select the intended audio input and output in your DAW. Confirm the project sample rate and recording destination, then record and play back a short test. Check monitoring delay before the performer starts; a successful device connection alone does not prove the recording path works.",
              source: "Focusrite · audio preparation", url: "https://support.focusrite.com/hc/en-gb/articles/207546515-Optimising-macOS-for-Audio"),
        .init(id: "buffer", title: "When audio crackles or monitoring feels delayed", scope: "Buffer size · any DAW",
              text: "Try one buffer-size change at a time and replay the same passage. A larger buffer gives audio processing more time but increases monitoring delay. A smaller buffer reduces that delay but leaves less processing time. Use your DAW’s audio settings; there is no universal best value.",
              source: "Focusrite · latency explained", url: "https://support.focusrite.com/hc/de/articles/207546885-What-is-latency-in-audio"),
        .init(id: "live", title: "Before a live set", scope: "Rehearsal · our recommendation",
              text: "Test the complete set with the interface, controllers, cables and power arrangement you will use. Close unrelated apps, keep required audio-control software running, and silence unwanted notifications. Avoid untested software or routing changes immediately before performing. These preparations reduce surprises; they cannot guarantee uninterrupted audio.",
              source: "Focusrite · preparing a Mac for audio", url: "https://support.focusrite.com/hc/en-gb/articles/207546515-Optimising-macOS-for-Audio"),
        .init(id: "memory", title: "When a project strains memory", scope: "Activity Monitor · any DAW",
              text: "Load the session and watch memory pressure during playback. Used RAM alone is not a problem: macOS also caches data. Sustained yellow or red pressure is a reason to investigate. Our recommendation: try reducing unused instruments or sample-library loads, then compare the same passage.",
              source: "Apple · memory pressure", url: "https://support.apple.com/en-gb/guide/activity-monitor/actmntr34865/mac"),
        .init(id: "storage", title: "Before a long recording", scope: "Recording-drive space · our recommendation",
              text: "Check free space on the drive receiving the recording, not only the Mac’s internal disk. Leave room for the planned session and temporary files. Review known files before removing anything; preserve recordings, recovery data, presets, sample libraries and licences.",
              source: "Focusrite · storage for audio", url: "https://support.focusrite.com/hc/en-gb/articles/207546515-Optimising-macOS-for-Audio"),
        .init(id: "backup", title: "Before updating the studio", scope: "Backup and compatibility · our recommendation",
              text: "Check support for your DAW, essential plugins and interface before changing macOS or audio software. Confirm a recent backup and that external project drives are included. Keep a way to return to your working setup. An inventory export is a list, not a backup of projects or software.",
              source: "Apple · Time Machine backup", url: "https://support.apple.com/en-us/104984"),
        .init(id: "maintenance", title: "Keep maintenance deliberate", scope: "Routine care · our recommendation",
              text: "Investigate a specific problem before clearing caches or changing system settings. Preserve unknown files and use the developer’s instructions for removal. A large cache alone is not a fault. Keep security protections enabled; generic optimisation checklists may include steps intended for different hardware.",
              source: "Focusrite · audio troubleshooting", url: "https://support.focusrite.com/hc/en-gb/articles/207546515-Optimising-macOS-for-Audio")
    ]
}

struct StudioTipsView: View {
    let search: String
    private var tips: [StudioTip] {
        StudioTip.all.filter { search.isEmpty || "\($0.title) \($0.scope) \($0.text)".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Prepare your Mac for audio work").font(.title2.weight(.semibold))
                Text("Practical preparation and troubleshooting for any DAW. Recommendations are labelled; sources reviewed on 8 September 2026.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Source links open independent websites. Their terms and privacy policies apply; linking does not imply endorsement of MK Studio Upkeep.")
                    .font(.caption).foregroundStyle(.secondary)
                if tips.isEmpty { Text("No tips match your search.").foregroundStyle(.secondary) }
                ForEach(tips) { tip in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tip.title).font(.headline)
                        Text(tip.scope).font(.caption).foregroundStyle(.secondary)
                        Text(tip.text).fixedSize(horizontal: false, vertical: true)
                        if let url = URL(string: tip.url) { Link("Read more: " + tip.source, destination: url).font(.caption).help(tip.source).accessibilityLabel("Read more: " + tip.title + ". " + tip.source) }
                    }
                    Divider()
                }
            }.frame(maxWidth: 760, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StudioTipsContextView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About these tips").font(.headline)
            Text("General guidance, not a diagnosis of this Mac. MK Studio Upkeep does not change settings or clean files from this page.")
            Text("The text is bundled and works offline. Source links open your browser; the destination site receives a normal web request.")
            Text("Guidance can change. Check the linked source for your current DAW and macOS version before acting.")
            Spacer()
        }.font(.subheadline).foregroundStyle(.secondary).padding(24)
    }
}
