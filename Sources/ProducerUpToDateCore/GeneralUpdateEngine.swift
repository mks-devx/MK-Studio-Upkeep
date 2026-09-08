// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Registry entries are maintainer-reviewed configuration, never URLs taken directly
/// from an installed bundle. A successful parser is not an access permission grant.
public enum GeneralUpdateEngine {
    public enum Reader: String, Codable, Sendable { case json, sparkle, githubLatest }
    public struct Product: Codable, Sendable {
        public let id: String
        public let bundleIDs: [String]
        public let edition: String
        public let format: String
        public let major: Int
        public let sourceID: String
    }
    public struct Source: Codable, Sendable {
        public let id: String
        public let endpoint: URL
        public let reader: Reader
        /// Nonempty only after a documented review. Not vendor endorsement.
        public let accessBasis: String?
        public let macAssetTemplate: String?
        public init(id: String, endpoint: URL, reader: Reader, accessBasis: String?, macAssetTemplate: String? = nil) {
            self.id = id; self.endpoint = endpoint; self.reader = reader
            self.accessBasis = accessBasis; self.macAssetTemplate = macAssetTemplate
        }
    }
    public struct Registry: Codable, Sendable {
        public let products: [Product]
        public let sources: [Source]
    }
    public struct Installation: Codable, Sendable {
        public let bundleID: String
        public let format: String
        public let version: String
        /// Uses detected identity/version only; no paths or personal metadata enter this layer.
        public init(record: PluginBundleRecord) {
            bundleID = record.bundleIdentifier ?? ""
            format = record.format.rawValue
            version = record.displayVersion ?? ""
        }
        public init(bundleID: String, format: String, version: String) {
            self.bundleID = bundleID; self.format = format; self.version = version
        }
    }
    public struct Release: Codable, Sendable {
        public let productID: String
        public let edition: String
        public let format: String
        public let platform: String
        public let version: String
    }
    public struct Observation: Sendable {
        public let releases: [Release]
        public let checkedAt: Date
    }
    public enum Status: Equatable, Sendable {
        case update(String), matches(String), ahead(String)
        case unknownIdentity, ambiguousIdentity, invalidVersion, sourceNotReviewed, sourceFailed, noMatchingRelease
    }
    public struct Result: Sendable {
        public let installation: Installation
        public let status: Status
        public let sourceURL: URL?
        public let checkedAt: Date?
    }
    public enum Failure: Error { case invalidRegistry, invalidFeed }
    public static let maximumBytes = 2_000_000
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public static func validate(_ registry: Registry) throws {
        guard registry.products.count <= 20_000, registry.sources.count <= 2_000,
              Set(registry.sources.map(\.id)).count == registry.sources.count,
              Set(registry.products.map(\.id)).count == registry.products.count else { throw Failure.invalidRegistry }
        for source in registry.sources {
            let url = source.endpoint
            guard !source.id.isEmpty, url.scheme == "https", let host = url.host, host.contains("."),
                  url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { throw Failure.invalidRegistry }
        }
        for product in registry.products {
            guard !product.id.isEmpty, !product.edition.isEmpty, !product.format.isEmpty, product.major > 0,
                  !product.bundleIDs.isEmpty, product.bundleIDs.allSatisfy({ !$0.isEmpty }),
                  registry.sources.contains(where: { $0.id == product.sourceID }) else { throw Failure.invalidRegistry }
        }
    }

    /// Runs once per distinct source, in bounded sequence; never sends installations.
    /// Unknown identities are a discovery backlog, not guessed current releases.
    public static func check(_ installations: [Installation], registry: Registry,
                             now: Date = Date(), fetch: Fetch) async throws -> [Result] {
        try validate(registry)
        var observations: [String: Observation] = [:]
        var attempted = Set<String>()
        var results: [Result] = []
        for installed in installations {
            try Task.checkCancellation()
            func result(_ status: Status, _ source: Source? = nil, _ date: Date? = nil) -> Result {
                Result(installation: installed, status: status, sourceURL: source?.endpoint, checkedAt: date)
            }
            guard let version = VersionComparator.parse(installed.version), version.channel == .stable else {
                results.append(result(.invalidVersion)); continue
            }
            let candidates = registry.products.filter {
                $0.bundleIDs.contains(installed.bundleID) && $0.format == installed.format && $0.major == version.numbers.first
            }
            guard candidates.count == 1, let product = candidates.first else {
                results.append(result(candidates.isEmpty ? .unknownIdentity : .ambiguousIdentity)); continue
            }
            let source = registry.sources.first { $0.id == product.sourceID }!
            guard let basis = source.accessBasis, !basis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results.append(result(.sourceNotReviewed, source)); continue
            }
            if attempted.insert(source.id).inserted {
                do {
                    let bytes = try await fetch(source.endpoint)
                    try Task.checkCancellation()
                    let releases = try parse(bytes, source: source, products: registry.products.filter { $0.sourceID == source.id })
                    observations[source.id] = Observation(releases: releases, checkedAt: now)
                } catch is CancellationError { throw CancellationError() }
                catch { /* A failed source remains failed for this batch. */ }
            }
            guard let observation = observations[source.id] else { results.append(result(.sourceFailed, source)); continue }
            let releases = observation.releases.filter {
                $0.productID == product.id && $0.edition == product.edition && $0.format == product.format && $0.platform == "macOS"
                && VersionComparator.parse($0.version)?.numbers.first == product.major
            }
            guard let latest = releases.max(by: { VersionComparator.compare($0.version, $1.version) == .older }) else {
                results.append(result(.noMatchingRelease, source, observation.checkedAt)); continue
            }
            let status: Status
            switch VersionComparator.compare(installed.version, latest.version) {
            case .older: status = .update(latest.version)
            case .equal: status = .matches(latest.version)
            case .newer: status = .ahead(latest.version)
            case .incomparable: status = .invalidVersion
            }
            results.append(result(status, source, observation.checkedAt))
        }
        return results
    }

    public static func parse(_ data: Data, source: Source, products: [Product]) throws -> [Release] {
        guard data.count <= maximumBytes else { throw Failure.invalidFeed }
        let releases: [Release]
        switch source.reader {
        case .githubLatest:
            releases = try GitHubAudioRelease.parse(data, source: source, products: products)
        case .json:
            guard JSONDepth.isWithinLimit(data) else { throw Failure.invalidFeed }
            releases = try JSONDecoder().decode([Release].self, from: data)
        case .sparkle:
            // A single-product feed is bound to one registry identity/edition/format.
            guard products.count == 1, let product = products.first,
                  let text = String(data: data, encoding: .utf8),
                  !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else { throw Failure.invalidFeed }
            let delegate = VersionAppcastParser()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.shouldProcessNamespaces = true
            parser.delegate = delegate
            guard parser.parse(), !delegate.invalid else { throw Failure.invalidFeed }
            releases = delegate.versions.map { Release(productID: product.id, edition: product.edition,
                format: product.format, platform: "macOS", version: $0) }
        }
        guard releases.count <= 10_000 else { throw Failure.invalidFeed }
        for release in releases {
            guard !release.productID.isEmpty, !release.edition.isEmpty, !release.format.isEmpty,
                  let version = VersionComparator.parse(release.version) else { throw Failure.invalidFeed }
            if version.channel != .stable { continue }
        }
        return releases.filter { VersionComparator.parse($0.version)?.channel == .stable }
    }
}

/// Deliberately supports a conservative subset of Sparkle. Rollouts, delta-only
/// entries, alternate platforms and nonstable channels cannot establish current status.
private final class VersionAppcastParser: NSObject, XMLParserDelegate {
    var versions: [String] = []
    var invalid = false
    private var inItem = false
    private var field: String?
    private var value = ""
    private var shortVersion: String?
    private var channel = ""
    private var eligible = true
    private let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "item" {
            if inItem { invalid = true }
            inItem = true; shortVersion = nil; channel = ""; eligible = true
        }
        guard inItem else { return }
        if namespaceURI == sparkle && ["shortVersionString", "channel"].contains(element) { field = element; value = "" }
        if namespaceURI == sparkle && ["phasedRolloutInterval", "deltas"].contains(element) { eligible = false }
        if element == "enclosure", attributes.contains(where: { ($0.key == "os" || $0.key.hasSuffix(":os")) && $0.value != "macos" }) { eligible = false }
        // Legacy enclosure version attributes are intentionally not inferred.
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if field != nil { value += string } }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if field == element && namespaceURI == sparkle {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if element == "shortVersionString" {
                if shortVersion != nil { invalid = true }
                shortVersion = text
            } else { channel = text }
            field = nil
        }
        if element == "item" {
            if eligible && channel.isEmpty, let version = shortVersion { versions.append(version) }
            inItem = false
        }
    }
}
