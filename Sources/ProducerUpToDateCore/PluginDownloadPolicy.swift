// SPDX-License-Identifier: MPL-2.0
import Foundation

/// A reviewed link is a browser handoff, not a verified or executed installer.
public enum PluginDownloadPolicy {
    public static func isAllowed(_ url: URL, for release: PluginReleaseRecord) -> Bool {
        guard release.vendorIdentifierPrefixes == ["com.d16group."],
              release.sourceURL.absoluteString == "https://d16.pl/installers",
              VersionComparator.parse(release.latestVersion)?.channel == .stable else { return false }
        // Exact versioned vendor-CDN paths. No redirects, tokens or "latest" URLs are
        // supplied by the catalogue. Browser redirects remain outside app control.
        return release.productAliases.contains { name in
            let slug = name.replacingOccurrences(of: " ", with: "")
            guard !slug.isEmpty, slug.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
            return url.absoluteString == "https://cdn.d16.pl/installers/\(slug)/\(slug)-\(release.latestVersion).dmg"
        }
    }
}
