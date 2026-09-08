// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Manual release discovery only. Never downloads or executes an installer.
public enum AppReleaseCheck {
    public static let maximumBytes = 2_000_000

    public struct Source: Equatable, Sendable {
        public let repository: String
        public init?(_ repository: String?) {
            guard let repository,
                  repository.range(of: #"\A[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}\z"#, options: .regularExpression) != nil else { return nil }
            self.repository = repository
        }
        public var endpoint: URL { URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100")! }
        public var releasesURL: URL { URL(string: "https://github.com/\(repository)/releases")! }
    }

    public static let projectSource = Source("mks-devx/MK-Studio-Upkeep")!

    public enum Result: Equatable, Sendable {
        case update(version: String, page: URL)
        case current(version: String)
        case ahead(version: String)
        case noReleases
    }

    public enum Failure: String, Error, LocalizedError {
        case response = "Could not check releases. Please try again later."
        case unavailable = "The public release source is not available yet."
        case rateLimited = "GitHub has limited update requests. Please try again later."
        case invalid = "Release information could not be compared safely. Open the release page to check manually."
        public var errorDescription: String? { rawValue }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]?
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let state: String
        let size: Int64
    }

    private static func hasInstaller(_ release: Release, source: Source) -> Bool {
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let installer = "MK-Studio-Upkeep-\(version)-macOS.dmg"
        func valid(_ name: String) -> Bool {
            release.assets?.contains { asset in
                let url = asset.browser_download_url
                return asset.name == name && asset.state == "uploaded" && asset.size > 0
                    && url.scheme == "https" && url.host == "github.com"
                    && url.user == nil && url.password == nil && url.port == nil
                    && url.query == nil && url.fragment == nil
                    && url.path == "/\(source.repository)/releases/download/\(release.tag_name)/\(name)"
            } == true
        }
        return valid(installer) && valid("SHA256SUMS.txt")
    }

    private static func versionValue(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"(?i)(alpha|beta|rc)\.([0-9]+)$"#, with: "$1$2", options: .regularExpression)
    }

    public static func evaluate(_ data: Data, source: Source, installed: String, includeBetas: Bool) throws -> Result {
        guard data.count <= maximumBytes, JSONDepth.isWithinLimit(data), VersionComparator.parse(versionValue(installed)) != nil,
              let releases = try? JSONDecoder().decode([Release].self, from: data), releases.count <= 100 else { throw Failure.invalid }
        var latest: Release?
        var skippedTags = 0
        for release in releases where !release.draft {
            if !includeBetas && release.prerelease { continue }
            // A tag that is not a version (for example a documentation tag) is skipped when a real
            // release exists alongside it; a list with nothing parseable is refused, not "current".
            guard let version = VersionComparator.parse(versionValue(release.tag_name)) else { skippedTags += 1; continue }
            if !includeBetas && version.channel != .stable { continue }
            let url = release.html_url
            guard url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
                  url.port == nil, url.query == nil, url.fragment == nil,
                  url.path == "/\(source.repository)/releases/tag/\(release.tag_name)" else { throw Failure.invalid }
            guard hasInstaller(release, source: source) else { continue }
            if latest == nil || VersionComparator.compare(versionValue(release.tag_name), versionValue(latest!.tag_name)) == .newer { latest = release }
        }
        if latest == nil, skippedTags > 0 { throw Failure.invalid }
        guard let latest else { return .noReleases }
        switch VersionComparator.compare(versionValue(installed), versionValue(latest.tag_name)) {
        case .older: return .update(version: latest.tag_name, page: latest.html_url)
        case .equal: return .current(version: latest.tag_name)
        case .newer: return .ahead(version: latest.tag_name)
        case .incomparable: throw Failure.invalid
        }
    }

    public static func check(source: Source, installed: String, includeBetas: Bool) async throws -> Result {
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: AppReleaseRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MK-Studio-Upkeep", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.response }
        if http.statusCode == 404 { throw Failure.unavailable }
        if http.statusCode == 403 || http.statusCode == 429 { throw Failure.rateLimited }
        guard http.statusCode == 200, http.url == source.endpoint,
              http.mimeType == "application/json", http.expectedContentLength <= maximumBytes else { throw Failure.response }
        // Refuse a partial release list rather than claim the app is current.
        if http.value(forHTTPHeaderField: "Link")?.contains("rel=\"next\"") == true { throw Failure.invalid }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw Failure.response }
            data.append(byte)
        }
        return try evaluate(data, source: source, installed: installed, includeBetas: includeBetas)
    }
}

private final class AppReleaseRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
