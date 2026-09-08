// SPDX-License-Identifier: BUSL-1.1
import Darwin
import Foundation

public enum MacProcessor: String, Sendable {
    case appleSilicon = "Apple Silicon"
    case intel = "Intel"
    case unknown = "Unknown processor"
}

/// The scanner's execution mode is not the DAW's mode, nor proof that Rosetta
/// is installed when this process is native. No plugin is loaded by this probe.
public struct MacArchitecture: Equatable, Sendable {
    public let processor: MacProcessor
    public let scannerIsTranslated: Bool?

    public init(processArchitecture: BinaryArchitecture, translated: Bool?) {
        scannerIsTranslated = translated
        if processArchitecture == .arm64 || translated == true {
            processor = .appleSilicon
        } else if processArchitecture == .x86_64 && translated == false {
            processor = .intel
        } else {
            processor = .unknown
        }
    }

    public static let current: MacArchitecture = {
        #if arch(arm64)
        let architecture = BinaryArchitecture.arm64
        #elseif arch(x86_64)
        let architecture = BinaryArchitecture.x86_64
        #else
        let architecture = BinaryArchitecture.unknown
        #endif
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        let value: Bool? = result == 0 ? translated == 1 : (errno == ENOENT ? false : nil)
        return MacArchitecture(processArchitecture: architecture, translated: value)
    }()
}

/// Classification of declared Mach-O CPU types, not executable validation or
/// a claim about dependencies, host support, signing or successful loading.
public enum InstalledArchitecture: Equatable, Sendable {
    case universal, intel64, appleSilicon, legacy32, unknown

    public static func classify(_ architectures: [BinaryArchitecture]) -> Self {
        let values = Set(architectures)
        guard !values.isEmpty, !values.contains(.unknown) else { return .unknown }
        if values.contains(.arm64) && values.contains(.x86_64) { return .universal }
        if values.contains(.arm64) { return .appleSilicon }
        if values.contains(.x86_64), values.isSubset(of: [.x86_64, .i386]) { return .intel64 }
        if values.isSubset(of: [.arm, .i386]) { return .legacy32 }
        return .unknown
    }
}

public extension InstalledArchitecture {
    /// CPU slices are local facts. These explanations deliberately do not certify loading or audio.
    func explanation(on processor: MacProcessor) -> String {
        switch self {
        case .universal:
            return "Contains Apple Silicon and Intel code. The plugin can supply either processor type; your DAW, macOS and plugin dependencies still need to be supported."
        case .intel64:
            switch processor {
            case .appleSilicon:
                return "Intel code only; on this Mac it runs through Rosetta. See the Intel section below."
            case .intel:
                return "Contains code for your Intel Mac. You do not need an Apple Silicon build on this Mac. DAW and macOS compatibility still need checking."
            case .unknown:
                return "Contains Intel code only. This Mac's processor could not be confirmed, so no processor-match conclusion is available."
            }
        case .appleSilicon:
            return processor == .intel
                ? "Contains Apple Silicon code only. It cannot run on an Intel Mac; look for an Intel or Universal installer for this product."
                : "Contains Apple Silicon code. Use a native Apple Silicon host for this code; its presence does not establish support for your exact DAW or macOS version."
        case .legacy32:
            return "Only 32-bit code was detected. Current macOS cannot run 32-bit plugins, and Rosetta 2 does not restore that support. Ask the vendor for a supported 64-bit replacement."
        case .unknown:
            return "The executable architecture could not be determined reliably. This is not proof of incompatibility. Check the vendor installer and inspect the file details."
        }
    }
}
