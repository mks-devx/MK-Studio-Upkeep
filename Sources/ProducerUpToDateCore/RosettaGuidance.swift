// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum GuidanceHost: String, CaseIterable, Identifiable, Sendable {
    case unspecified = "Choose your DAW"
    case logic = "Logic Pro"
    case live = "Ableton Live 11.1 or later"
    case other = "Another DAW"
    public var id: String { rawValue }
}

/// General host documentation, deliberately separate from product/release
/// support records. Selecting a host does not certify any installed plugin.
public struct RosettaHostGuidance: Sendable {
    public let detail: String
    public let sourceURL: URL
    public let reviewedOn: String
    public let isFresh: Bool

    public static func guidance(host: GuidanceHost, formats: Set<PluginFormat>,
                                now: Date = Date()) -> Self? {
        let date = "2026-09-05"
        let fresh = EvidenceFreshness.isFresh(date, now: now)
        let source: URL
        let detail: String
        switch host {
        case .logic:
            guard formats.contains(.audioUnit) else { return nil }
            source = URL(string: "https://support.apple.com/en-us/102082")!
            detail = "Apple documents Intel Audio Unit hosting with Rosetta installed. ARA can require Logic itself to run through Rosetta. Check the exact plugin and Logic version before changing how your DAW opens. This guidance applies to Audio Units only."
        case .live:
            guard !formats.isDisjoint(with: [.audioUnit, .vst2, .vst3]) else { return nil }
            source = URL(string: "https://help.ableton.com/hc/en-us/articles/4410323149074-Plug-ins-on-Mac-in-Live-11-1-and-later")!
            var parts: [String] = []
            if !formats.isDisjoint(with: [.vst2, .vst3]) {
                parts.append("Native Live requires native VST2/VST3 builds. Ableton documents opening Live through Rosetta for Intel VST plugins.")
            }
            if formats.contains(.audioUnit) {
                parts.append("Many Intel Audio Units can load through macOS translation while Live stays native; some still require Live through Rosetta.")
            }
            parts.append("Check the instructions for your Live version. This does not confirm support for this plugin or other formats.")
            detail = parts.joined(separator: " ")
        case .unspecified, .other:
            return nil
        }
        return Self(detail: fresh ? detail : "These host instructions need a fresh review. Check the official source for current requirements.",
                    sourceURL: source, reviewedOn: date, isFresh: fresh)
    }
}
