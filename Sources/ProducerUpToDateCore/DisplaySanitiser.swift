// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Text read from other people's bundles is shown verbatim, so it is first stripped of
/// characters that can disguise it (controls, bidirectional overrides, zero-width marks)
/// and bounded in length so a hostile or broken metadata value cannot stall layout.
public enum DisplaySanitiser {
    public static let defaultMaximumLength = 256

    private static let invisible: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        for value in [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF, 0x2028, 0x2029] { set.insert(Unicode.Scalar(UInt32(value))!) }
        for value in 0x202A...0x202E { set.insert(Unicode.Scalar(UInt32(value))!) }
        for value in 0x2066...0x2069 { set.insert(Unicode.Scalar(UInt32(value))!) }
        return set
    }()

    /// Removes control and direction-altering scalars, collapses surrounding whitespace and
    /// truncates to `maximumLength` characters. Returns nil when nothing readable remains.
    public static func sanitise(_ value: String, maximumLength: Int = defaultMaximumLength) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars where !invisible.contains(scalar)
            && scalar.properties.generalCategory != .format
            && !(scalar.properties.generalCategory == .control && scalar != "\t") {
            scalars.append(scalar)
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > maximumLength ? String(trimmed.prefix(maximumLength)) : trimmed
    }
}
