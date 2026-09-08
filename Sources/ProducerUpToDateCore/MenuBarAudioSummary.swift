// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum MenuBarAudioSummary {
    public static let preferenceKey = "showMenuBarAudio"

    public static func title(for output: AudioOutputSnapshot?, locale: Locale = .current) -> String {
        guard let output else { return "Audio unavailable" }
        let rate = output.sampleRate.map {
            ($0 / 1000).formatted(.number.precision(.fractionLength(0...3)).locale(locale)) + " kHz"
        } ?? "— kHz"
        let depth: String
        if let depths = output.bitDepths, depths.count == 1, let value = depths.first {
            depth = "\(value)-bit"
        } else if let depths = output.bitDepths, depths.count > 1 {
            depth = "mixed bits"
        } else { depth = "— bit" }
        let buffer = output.bufferFrames.map { "\($0) fr" } ?? "— fr"
        return "\(rate) · \(depth) · \(buffer)"
    }

    public static func detail(for output: AudioOutputSnapshot?) -> String {
        guard let output else { return "macOS output device unavailable. Your DAW may use another device." }
        let rate = output.sampleRate.map { $0.formatted() + " Hz" } ?? "unavailable"
        let buffer = output.bufferFrames.map { "\($0) frames" } ?? "unavailable"
        let depths = output.bitDepths.map { $0.map { "\($0)-bit" }.joined(separator: " / ") } ?? "unavailable"
        return "macOS output: \(output.name). Sample rate: \(rate). Device bit depth: \(depths). Buffer: \(buffer). Your DAW may use different settings."
    }
}
