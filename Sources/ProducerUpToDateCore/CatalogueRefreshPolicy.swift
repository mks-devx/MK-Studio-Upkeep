// SPDX-License-Identifier: MPL-2.0
import Foundation

/// A build-configured public feed; never derived from local inventory.
public enum CatalogueRefreshPolicy {
    public static func endpoint(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    public static func shouldCheck(enabled: Bool, lastAttempt: Date?, now: Date = Date()) -> Bool {
        guard enabled else { return false }
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        return elapsed >= 86_400 || elapsed < 0
    }
}
