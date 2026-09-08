// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Addresses declared in installed metadata. Detection performs no network request
/// and does not establish release currency or independent ownership verification.
public struct DeclaredProductLink: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case website, updateFeed }
    public let kind: Kind
    public let url: URL
    public init?(kind: Kind, value: String) {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.utf8.count <= 2048, let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), host.contains("."),
              host.range(of: #"\A[a-z0-9.-]+\z"#, options: .regularExpression) != nil,
              host.contains(where: { $0.isLetter }),
              !["local", "localhost", "internal", "invalid", "test"].contains(host.split(separator: ".").last.map(String.init) ?? ""),
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              !raw.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        self.kind = kind; self.url = url
    }
    private enum CodingKeys: String, CodingKey { case kind, url }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(Kind.self, forKey: .kind)
        let url = try values.decode(URL.self, forKey: .url)
        guard let validated = Self(kind: kind, value: url.absoluteString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: values, debugDescription: "Unsupported declared address")
        }
        self = validated
    }
    public static func extract(plist: [String: Any]?, moduleInfo: [String: Any]?) -> [DeclaredProductLink] {
        var result: [DeclaredProductLink] = []
        if let raw = plist?["SUFeedURL"] as? String, let feed = DeclaredProductLink(kind: .updateFeed, value: raw) { result.append(feed) }
        if let factory = moduleInfo?["Factory Info"] as? [String: Any], let raw = factory["URL"] as? String,
           let site = DeclaredProductLink(kind: .website, value: raw) { result.append(site) }
        return result
    }
}
