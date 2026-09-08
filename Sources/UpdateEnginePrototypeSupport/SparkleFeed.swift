// SPDX-License-Identifier: BUSL-1.1
import Foundation
import ProducerUpToDateCore

public enum FeedFailure: String, Error, LocalizedError, Sendable {
    case unsafeAddress = "The feed address is not supported for an automatic check."
    case network = "The feed could not be fetched safely."
    case malformed = "The feed is malformed or exceeds the prototype limits."
    case unsupported = "This feed uses unsupported release conditions or version formats."
    case noStableRelease = "No comparable stable macOS release was found."
    case version = "The installed build number cannot be compared safely."
    public var errorDescription: String? { rawValue }
}

public struct FeedRelease: Sendable, Equatable {
    public let build: String
    public let version: String
    public let minimumOS: String?
    public let maximumOS: String?
    public let minimumBuild: String?
    public let upgradeBoundary: String?
    public let hardware: String?
}

/// Deliberately narrow RSS/Sparkle subset. No DTD, external entity, HTML rendering,
/// installer download, version inference from titles, or fallback to text scraping.
public enum SparkleFeed {
    public static let maximumBytes = 524_288
    public static let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    public static func parse(_ data: Data) throws -> [FeedRelease] {
        guard data.count <= maximumBytes, !data.contains(0), let text = String(data: data, encoding: .utf8),
              !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else { throw FeedFailure.malformed }
        let reader = FeedXMLReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), !reader.invalid, reader.itemCount > 0 else { throw FeedFailure.malformed }
        guard !reader.unsupported else { throw FeedFailure.unsupported }
        guard !reader.releases.isEmpty else { throw FeedFailure.noStableRelease }
        return reader.releases
    }
}

private final class FeedXMLReader: NSObject, XMLParserDelegate {
    var invalid = false
    var unsupported = false
    var releases: [FeedRelease] = []
    var itemCount = 0
    private var stack: [(String, String)] = []
    private var namespaces: [String: String] = [:]
    private var item: [String: String]?
    private var text = ""
    private let fields: Set<String> = ["version", "shortVersionString", "minimumSystemVersion", "maximumSystemVersion", "minimumUpdateVersion", "minimumAutoupdateVersion", "hardwareRequirements", "channel"]
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        if let previous = namespaces[prefix], previous != namespaceURI { invalid = true; parser.abortParsing() }
        namespaces[prefix] = namespaceURI
    }
    private func put(_ key: String, _ value: String, parser: XMLParser) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 128, item?[key] == nil || item?[key] == value else { invalid = true; parser.abortParsing(); return }
        item?[key] = value
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append((name, namespaceURI ?? "")); text = ""
        guard stack.count <= 16 else { invalid = true; parser.abortParsing(); return }
        if stack.count == 1, name != "rss" || !(namespaceURI ?? "").isEmpty { invalid = true; parser.abortParsing() }
        if stack.count == 5, stack[3].1 == SparkleFeed.namespace, fields.contains(stack[3].0) {
            unsupported = true
        }
        if name == "item", (namespaceURI ?? "").isEmpty {
            guard stack.count == 3, stack[1].0 == "channel", stack[1].1.isEmpty else { invalid = true; parser.abortParsing(); return }
            itemCount += 1
            guard itemCount <= 200 else { invalid = true; parser.abortParsing(); return }
            item = [:]
        }
        guard item != nil else { return }
        if stack.count == 4, name == "enclosure", (namespaceURI ?? "").isEmpty {
            if item?["enclosure"] != nil { unsupported = true }
            item?["enclosure"] = "yes"
            for (key, value) in attributes {
                let parts = key.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, namespaces[String(parts[0])] == SparkleFeed.namespace else { continue }
                let field = String(parts[1])
                if fields.contains(field) { put(field, value, parser: parser) }
                if field == "os", value != "macos" { item?["nonMac"] = "yes" }
            }
        }
        if namespaceURI == SparkleFeed.namespace, stack.count == 4,
           !fields.contains(name), !["releaseNotesLink", "fullReleaseNotesLink", "criticalUpdate", "phasedRolloutInterval"].contains(name) {
            unsupported = true
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Only collect short, directly relevant field text; ignore HTML descriptions.
        guard stack.count == 4, let last = stack.last, last.1 == SparkleFeed.namespace, fields.contains(last.0) else { return }
        text += string
        if text.utf8.count > 128 { invalid = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
        else { invalid = true; parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if stack.count == 4, namespaceURI == SparkleFeed.namespace, fields.contains(name) { put(name, text, parser: parser) }
        if stack.count == 3, name == "item", (namespaceURI ?? "").isEmpty { finishItem(); item = nil }
        if !stack.isEmpty { stack.removeLast() }; text = ""
    }
    private func finishItem() {
        guard let item else { return }
        if item["nonMac"] != nil || !(item["channel"] ?? "").isEmpty { return }
        guard let build = item["version"], let parsed = VersionComparator.parse(build) else { unsupported = true; return }
        let version = item["shortVersionString"] ?? build
        guard let display = VersionComparator.parse(version) else { unsupported = true; return }
        if parsed.channel != .stable || display.channel != .stable { return }
        for key in ["minimumSystemVersion", "maximumSystemVersion", "minimumUpdateVersion", "minimumAutoupdateVersion"] {
            if let value = item[key], VersionComparator.parse(value)?.channel != .stable { unsupported = true; return }
        }
        if let hardware = item["hardwareRequirements"], hardware != "arm64" { unsupported = true; return }
        releases.append(FeedRelease(build: build, version: version,
            minimumOS: item["minimumSystemVersion"], maximumOS: item["maximumSystemVersion"],
            minimumBuild: item["minimumUpdateVersion"], upgradeBoundary: item["minimumAutoupdateVersion"],
            hardware: item["hardwareRequirements"]))
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        invalid = true; parser.abortParsing(); return nil
    }
}

public struct FeedComparison: Sendable {
    public let update: FeedRelease?
    public let newerEdition: FeedRelease?
    public let source: URL
    public let checkedAt: Date
    public var noUpdateFound: Bool { update == nil && newerEdition == nil }
    public func isFresh(at date: Date = Date()) -> Bool { (0...86_400).contains(date.timeIntervalSince(checkedAt)) }

    public static func evaluate(_ releases: [FeedRelease], installedBuild: String?, source: URL,
                                macOS: String, appleSilicon: Bool, now: Date = Date()) throws -> Self {
        guard let installedBuild, VersionComparator.parse(installedBuild)?.channel == .stable else { throw FeedFailure.version }
        guard VersionComparator.parse(macOS)?.channel == .stable else { throw FeedFailure.unsupported }
        // Same build with conflicting release conditions is not one reliable result.
        guard releases.count <= 200 else { throw FeedFailure.malformed }
        for (index, release) in releases.enumerated() {
            for other in releases.dropFirst(index + 1) where VersionComparator.compare(release.build, other.build) == .equal {
                guard release == other else { throw FeedFailure.unsupported }
            }
        }
        var update: FeedRelease?
        var upgrade: FeedRelease?
        var eligible = 0
        for release in releases {
            if let min = release.minimumOS, VersionComparator.compare(macOS, min) == .older { continue }
            if let max = release.maximumOS, VersionComparator.compare(macOS, max) == .newer { continue }
            if let min = release.minimumBuild, VersionComparator.compare(installedBuild, min) == .older { continue }
            if release.hardware == "arm64" && !appleSilicon { continue }
            eligible += 1
            guard VersionComparator.compare(installedBuild, release.build) == .older else { continue }
            if let boundary = release.upgradeBoundary, VersionComparator.compare(installedBuild, boundary) == .older {
                if upgrade == nil || VersionComparator.compare(release.build, upgrade!.build) == .newer { upgrade = release }
            } else if update == nil || VersionComparator.compare(release.build, update!.build) == .newer { update = release }
        }
        guard eligible > 0 else { throw FeedFailure.noStableRelease }
        return Self(update: update, newerEdition: upgrade, source: source, checkedAt: now)
    }
}
