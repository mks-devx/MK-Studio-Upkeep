// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Test coverage and feature availability are separate. Untested does not mean unsupported.
public enum TestedPlatform {
    public static let requirements = "Requires macOS 13 or later. Tested on Apple Silicon with macOS 26.5.2. Other macOS versions and Intel Macs have not yet been tested."
    public static let removalUnavailable = "In-app removal requires macOS 13 or later."
    public static let removalCaution = "Removal is experimental and has not been tested on this Mac configuration. Review the selected items carefully before confirming."

    public static func isTested(isNativeAppleSilicon: Bool, version: OperatingSystemVersion) -> Bool {
        isNativeAppleSilicon && version.majorVersion == 26 && version.minorVersion == 5 && version.patchVersion == 2
    }

    public static func permitsRemoval(isNativeAppleSilicon: Bool, version: OperatingSystemVersion) -> Bool {
        // Removal uses the same reviewed-file safeguards on both supported architectures.
        version.majorVersion >= 13
    }

    private static var isNativeAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    public static var isTestedConfiguration: Bool {
        isTested(isNativeAppleSilicon: isNativeAppleSilicon, version: ProcessInfo.processInfo.operatingSystemVersion)
    }

    public static var removalAllowed: Bool {
        permitsRemoval(isNativeAppleSilicon: isNativeAppleSilicon, version: ProcessInfo.processInfo.operatingSystemVersion)
    }
}
