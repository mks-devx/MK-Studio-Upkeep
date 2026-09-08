// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ReleaseChannel: Int, Codable, Comparable, Sendable {
    case alpha = 0
    case beta = 1
    case releaseCandidate = 2
    case stable = 3

    public static func < (lhs: ReleaseChannel, rhs: ReleaseChannel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ComparableVersion: Equatable, Codable, Sendable {
    public let original: String
    public let numbers: [Int]
    public let channel: ReleaseChannel
    public let prereleaseNumber: Int?

    public init(
        original: String,
        numbers: [Int],
        channel: ReleaseChannel,
        prereleaseNumber: Int?
    ) {
        self.original = original
        self.numbers = numbers
        self.channel = channel
        self.prereleaseNumber = prereleaseNumber
    }
}

public enum VersionComparison: Equatable, Sendable {
    case older
    case equal
    case newer
    case incomparable
}

public enum VersionComparator {
    /// Longest version string accepted from bundles, catalogues or network responses.
    public static let maximumLength = 64
    private static let prereleasePattern = try! NSRegularExpression(
        pattern: #"(?i)(?:[\s._-]*)(alpha|a|beta|b|rc)\s*([0-9]*)$"#
    )

    public static func parse(_ rawValue: String) -> ComparableVersion? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Real version strings are a few dozen characters. The cap also keeps the prerelease
        // regular expression, which is quadratic in the worst case, on trivially small input.
        guard !value.isEmpty, value.utf8.count <= maximumLength else {
            return nil
        }

        if value.count >= 2,
           value.first?.lowercased() == "v",
           value.dropFirst().first?.isNumber == true {
            value.removeFirst()
        }

        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let prereleaseMatch = prereleasePattern.firstMatch(
            in: value,
            range: fullRange
        )
        var channel = ReleaseChannel.stable
        var prereleaseNumber: Int?
        var numericPart = value

        if let prereleaseMatch,
           let labelRange = Range(prereleaseMatch.range(at: 1), in: value),
           let fullMatchRange = Range(prereleaseMatch.range(at: 0), in: value) {
            let label = value[labelRange].lowercased()
            switch label {
            case "alpha", "a":
                channel = .alpha
            case "beta", "b":
                channel = .beta
            case "rc":
                channel = .releaseCandidate
            default:
                return nil
            }

            if let numberRange = Range(prereleaseMatch.range(at: 2), in: value) {
                let number = String(value[numberRange])
                prereleaseNumber = number.isEmpty ? nil : Int(number)
            }
            numericPart.removeSubrange(fullMatchRange)
        }

        let normalized = numericPart
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard
            !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }

        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else {
            return nil
        }

        return ComparableVersion(
            original: rawValue,
            numbers: numbers,
            channel: channel,
            prereleaseNumber: prereleaseNumber
        )
    }

    /// Keep prerelease channels. Only the documented numeric build suffix is discarded.
    public static func releaseValue(_ raw: String) -> String? {
        guard raw.utf8.count <= 2 * maximumLength else { return nil }
        if parse(raw) != nil { return raw }
        let pattern = #"^([vV]?[0-9]+(?:\.[0-9]+)*) \([0-9]{4}-[0-9]{2}-[0-9]{2}_(?:build|[0-9a-f]{10,40})\)$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              let capture = Range(match.range(at: 1), in: raw) else { return nil }
        return String(raw[capture])
    }

    public static func compare(_ lhs: String, _ rhs: String) -> VersionComparison {
        guard let lhs = parse(lhs), let rhs = parse(rhs) else {
            return .incomparable
        }

        let componentCount = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<componentCount {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left < right {
                return .older
            }
            if left > right {
                return .newer
            }
        }

        if lhs.channel < rhs.channel {
            return .older
        }
        if lhs.channel > rhs.channel {
            return .newer
        }

        let leftPrerelease = lhs.prereleaseNumber ?? 0
        let rightPrerelease = rhs.prereleaseNumber ?? 0
        if leftPrerelease < rightPrerelease {
            return .older
        }
        if leftPrerelease > rightPrerelease {
            return .newer
        }

        return .equal
    }
}
