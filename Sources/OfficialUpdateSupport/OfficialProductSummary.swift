// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum OfficialProductSummary {
    public static func label(total: Int, results: [OfficialObservation], now: Date) -> String {
        let states = results.map { $0.state(at: now) }
        let updates = states.filter { $0 == .update }.count
        if updates > 0 { return "Update available · \(updates) of \(total) copies" }
        if states.contains(.stale) { return "Check expired" }
        if states.contains(.failed) { return "Check failed" }
        if states.contains(.ambiguous) { return "Could not compare" }
        if results.isEmpty { return "Automatic check available" }
        if results.count != total { return "Partly checked · \(results.count) of \(total) copies" }
        if states.contains(.ahead) { return "Installed copy newer than source" }
        return "Matches official release"
    }
}
