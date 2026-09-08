// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// A linear pre-check before untrusted bytes reach `JSONDecoder`: pathologically nested arrays
/// or objects can exhaust the recursive parser's stack, so anything nested beyond `limit` is
/// refused first. Strings are skipped so brackets inside them do not count.
public enum JSONDepth {
    public static let limit = 32

    public static func isWithinLimit(_ data: Data, limit: Int = limit) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x7B, 0x5B:
                depth += 1
                if depth > limit { return false }
            case 0x7D, 0x5D: depth -= 1
            default: break
            }
        }
        return true
    }
}
