// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Reads release metadata only; assets are neither downloaded nor executed.
/// A registry-specific Mac asset name must corroborate the numeric stable tag.
enum GitHubAudioRelease {
    private struct Entry: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }
    static func parse(_ data: Data, source: GeneralUpdateEngine.Source,
                      products: [GeneralUpdateEngine.Product]) throws -> [GeneralUpdateEngine.Release] {
        typealias E = GeneralUpdateEngine
        let parts = source.endpoint.path.split(separator: "/")
        guard data.count <= E.maximumBytes, source.endpoint.scheme == "https", source.endpoint.host == "api.github.com",
              source.endpoint.user == nil, source.endpoint.password == nil, source.endpoint.port == nil,
              source.endpoint.query == nil, source.endpoint.fragment == nil,
              parts.count == 5, parts[0] == "repos", parts[3] == "releases", parts[4] == "latest",
              products.count == 1, let product = products.first,
              let template = source.macAssetTemplate, template.contains("{version}"),
              !template.contains("/"), !template.contains("\\") else { throw E.Failure.invalidFeed }
        guard JSONDepth.isWithinLimit(data) else { throw E.Failure.invalidFeed }
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        guard !entry.draft, !entry.prerelease, entry.assets.count <= 200,
              entry.tag_name.range(of: #"\Av?[0-9]+(?:\.[0-9]+){1,3}\z"#, options: .regularExpression) != nil else { throw E.Failure.invalidFeed }
        let version = entry.tag_name.hasPrefix("v") ? String(entry.tag_name.dropFirst()) : entry.tag_name
        let repository = "\(parts[1])/\(parts[2])"
        guard entry.html_url.absoluteString == "https://github.com/\(repository)/releases/tag/\(entry.tag_name)" else { throw E.Failure.invalidFeed }
        let expected = template.replacingOccurrences(of: "{version}", with: version)
        let matches = entry.assets.filter { $0.name == expected }
        guard matches.count == 1, matches[0].browser_download_url.absoluteString == "https://github.com/\(repository)/releases/download/\(entry.tag_name)/\(expected)" else { throw E.Failure.invalidFeed }
        return [.init(productID: product.id, edition: product.edition, format: product.format, platform: "macOS", version: version)]
    }
}
