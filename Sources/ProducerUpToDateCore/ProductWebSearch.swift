// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Browser navigation for any locally detected product. No supported-product list,
/// API credentials, background requests or interpretation of search results.
public enum ProductSearchProvider: String, CaseIterable, Identifiable, Sendable {
    case duckDuckGo = "DuckDuckGo"
    case google = "Google"
    public var id: String { rawValue }
    public var destination: URL {
        switch self {
        case .duckDuckGo: URL(string: "https://duckduckgo.com/")!
        case .google: URL(string: "https://www.google.com/search")!
        }
    }
    public func url(query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 512,
              !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        var components = URLComponents(url: destination, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url, url.absoluteString.utf8.count <= 7500 else { return nil }
        return url
    }
}
public enum ProductWebSearch {
    public static func suggestedQuery(product: String, developer: String?) -> String {
        let name = DisplaySanitiser.sanitise(product, maximumLength: 160) ?? ""
        let vendor = developer.flatMap { DisplaySanitiser.sanitise($0, maximumLength: 100) } ?? ""
        return [name, vendor, "official download release notes macOS"].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
