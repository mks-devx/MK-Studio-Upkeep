// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum PluginCategory: String, CaseIterable, Sendable {
    case instrument = "Instrument"
    case audioEffect = "Audio Effect"
    case midiEffect = "MIDI Effect"
    case uncategorised = "Uncategorised"

    /// Only explicit static metadata participates. Missing metadata is not a contradiction.
    /// Mixed component types remain unknown rather than guessing a container's primary role.
    public static func classify(evidence: [VersionEvidence]) -> Self {
        var categories = Set<String>()
        for item in evidence {
            if item.kind == .audioComponent && item.field.hasSuffix(".type") {
                switch item.value {
                case "aumu": categories.insert(Self.instrument.rawValue)
                case "aufx", "aumf": categories.insert(Self.audioEffect.rawValue)
                case "aumi": categories.insert(Self.midiEffect.rawValue)
                default: categories.insert(Self.uncategorised.rawValue)
                }
            } else if item.kind == .vst3ModuleInfo && item.field.hasSuffix(".Sub Categories") {
                let tokens = Set(item.value.split(separator: "|").map(String.init))
                if tokens.contains("Instrument") { categories.insert(Self.instrument.rawValue) }
                if tokens.contains("Fx") { categories.insert(Self.audioEffect.rawValue) }
                if !tokens.contains("Instrument") && !tokens.contains("Fx") {
                    categories.insert(Self.uncategorised.rawValue)
                }
            }
        }
        guard categories.count == 1, let value = categories.first else { return .uncategorised }
        return Self(rawValue: value) ?? .uncategorised
    }
}

extension NormalizedPluginProduct {
    public var category: PluginCategory { .classify(evidence: bundles.flatMap(\.evidence)) }
}

/// Product-role tags from static VST3 metadata only; no name guessing or plugin loading.
public enum PluginRoleTags {
    private static let mapping = [
        "EQ": "EQ", "Dynamics": "Dynamics", "Delay": "Delay", "Reverb": "Reverb",
        "Distortion": "Distortion", "Modulation": "Modulation", "Filter": "Filter",
        "Pitch Shift": "Pitch", "Restoration": "Restoration", "Analyzer": "Analysis",
        "Tools": "Utility", "Spatial": "Spatial", "Channel Strip": "Channel Strip",
        "Synth": "Synthesizer", "Sampler": "Sampler", "Drum": "Drums", "Piano": "Piano"
    ]
    public static let all = Array(Set(mapping.values)).sorted()
    public static func classify(evidence: [VersionEvidence]) -> [String] {
        let tags = evidence.filter { $0.kind == .vst3ModuleInfo && $0.field.hasSuffix(".Sub Categories") }
            .flatMap { $0.value.split(separator: "|").compactMap { mapping[$0.trimmingCharacters(in: .whitespacesAndNewlines)] } }
        return Array(Set(tags)).sorted()
    }
}

extension NormalizedPluginProduct {
    public var roleTags: [String] { PluginRoleTags.classify(evidence: bundles.flatMap(\.evidence)) }
}

/// Counts the current candidate set once, independently of the selected category.
/// Rebuild from current candidates so rescans and other filters cannot leave stale counts.
public struct PluginCategoryCounts: Sendable {
    public let total: Int
    public private(set) var categories: [PluginCategory: Int] = [:]
    public private(set) var roles: [String: Int] = [:]

    public init(products: [NormalizedPluginProduct]) {
        total = products.count
        for product in products {
            let evidence = product.bundles.flatMap(\.evidence)
            categories[PluginCategory.classify(evidence: evidence), default: 0] += 1
            for role in PluginRoleTags.classify(evidence: evidence) {
                roles[role, default: 0] += 1
            }
        }
    }
}
