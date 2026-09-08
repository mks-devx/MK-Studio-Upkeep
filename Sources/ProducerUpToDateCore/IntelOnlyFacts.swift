// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Whether Apple's Intel translation layer is present. Read from the file system only;
/// nothing is launched. Presence says a plug-in can be loaded, never that it behaves.
public enum RosettaStatus: Equatable, Sendable {
    /// An Intel Mac runs Intel code natively.
    case notNeeded
    case installed
    case missing
    case unknown

    static let markers = ["/Library/Apple/usr/share/rosetta/rosetta", "/Library/Apple/usr/libexec/oah/libRosettaRuntime"]

    public static func detect(processor: MacProcessor = MacArchitecture.current.processor,
                              fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> RosettaStatus {
        switch processor {
        case .intel: return .notNeeded
        case .unknown: return .unknown
        case .appleSilicon: return markers.contains(where: fileExists) ? .installed : .missing
        }
    }

    /// One plain sentence for the facts block.
    public var sentence: String {
        switch self {
        case .notNeeded: "This Mac has an Intel processor, so Intel plug-ins run natively."
        case .installed: "Rosetta is installed, so this Mac can load Intel code. That is not a promise about how the plug-in behaves."
        case .missing: "Rosetta is not installed, so Intel-only plug-ins cannot load on this Mac. macOS offers to install it the first time an Intel app opens, or run: softwareupdate --install-rosetta"
        case .unknown: "The processor could not be determined, so Rosetta requirements are unknown."
        }
    }
}

public extension GuidanceHost {
    /// Preselects the DAW picker from the DAWs actually installed. Two supported hosts, or
    /// none, leave the choice to the user rather than guessing.
    static func detected(installedDefinitionIDs: [String]) -> GuidanceHost {
        let ids = Set(installedDefinitionIDs)
        let logic = ids.contains("logic-pro"), live = ids.contains("ableton-live")
        switch (logic, live) {
        case (true, false): return .logic
        case (false, true): return .live
        case (true, true): return .unspecified
        case (false, false): return ids.isEmpty ? .unspecified : .other
        }
    }
}

/// Three facts a user can act on for an Intel-only product, each traceable to evidence the
/// app actually has: what the files contain, whether the vendor has a native release on
/// record, and whether this Mac can load Intel code at all. Stability is never one of them.
public struct IntelOnlyFacts: Equatable, Sendable {
    public let files: String
    public let nativeVersion: String
    public let rosetta: String

    public init(product: NormalizedPluginProduct, nativeCheck: ProductArchitectureCheckResult, rosetta: RosettaStatus) {
        let formats = Set(PluginGuidance.intelOnlyBundles(product).map(\.format.rawValue)).sorted().joined(separator: " + ")
        files = "Intel-only files: \(formats.isEmpty ? "none" : formats). Read from the executable headers; the plug-in was not loaded."
        switch nativeCheck {
        case let .nativeReleaseAvailable(upgrade):
            nativeVersion = "Native version on record: \(upgrade.version) (\(upgrade.formats.map(\.rawValue).sorted().joined(separator: " + "))), reviewed \(upgrade.checkedOn)."
        case .nativeReleaseNotConfirmed, .notApplicable:
            nativeVersion = "Native version: not on record. The vendor may have one; the catalogue has no reviewed entry for this product."
        case let .evidenceOutdated(_, checkedOn):
            nativeVersion = "Native version: the record from \(checkedOn) needs a fresh review before it can be relied on."
        case let .needsVerification(reason):
            nativeVersion = "Native version: cannot be looked up yet. \(reason)"
        }
        self.rosetta = rosetta.sentence
    }
}
