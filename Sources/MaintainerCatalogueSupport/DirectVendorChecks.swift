// SPDX-License-Identifier: MPL-2.0
import Foundation
import ProducerUpToDateCore

/// Fixed public destinations, independent of the user's inventory. No credentials or installers.
public enum DirectVendor: String, CaseIterable, Codable, Sendable {
    case d16, kilohearts, fabfilter, tdrNova, tdrKotelnikov, tdrMolotok, logic, live, reaper, garageband, reason
    /// No live plugin or DAW release readers are enabled in the distributable app.
    /// Parsing utilities remain for fixtures and maintainer tooling.
    public static let active: [DirectVendor] = []
    public var isActive: Bool { Self.active.contains(self) }
    /// Why no live release check is offered by the maintainer tool.
    public var inactiveReason: String? {
        switch self {
        case .logic, .garageband: "App Store receipt handoff; Apple's site terms restrict automated reading."
        case .fabfilter, .kilohearts, .tdrNova, .tdrKotelnikov, .tdrMolotok, .live, .reaper: "No catalogue is bundled; no live reader is configured."
        case .d16: "No catalogue is bundled; no live reader is configured."
        case .reason: "No documented access basis; official website handoff only."
        }
    }
    /// robots.txt crawl-delay observed on 2026-09-06; the other hosts declare none.
    public var crawlDelay: TimeInterval { self == .kilohearts ? 1.5 : 0 }
    /// A public API built for clients, not a website to be paced.
    public var isPublicAPI: Bool { false }
    public var name: String {
        switch self { case .reason: "Reason 14"; case .fabfilter: "FabFilter"; case .tdrNova: "TDR Nova"; case .tdrKotelnikov: "TDR Kotelnikov"; case .tdrMolotok: "TDR Molotok"; case .d16: "D16"; case .kilohearts: "Kilohearts"; case .logic: "Logic Pro for Mac"; case .live: "Ableton Live 12"; case .reaper: "REAPER"; case .garageband: "GarageBand for Mac" }
    }
    public var url: URL {
        switch self {
        case .fabfilter: URL(string: "https://www.fabfilter.com/download")!
        case .tdrNova: URL(string: "https://www.tokyodawn.net/tdr-nova/")!
        case .tdrKotelnikov: URL(string: "https://www.tokyodawn.net/tdr-kotelnikov/")!
        case .tdrMolotok: URL(string: "https://www.tokyodawn.net/tdr-molotok/")!
        case .d16: URL(string: "https://d16.pl/installers")!
        case .kilohearts: URL(string: "https://kilohearts.com/download")!
        case .reason: URL(string: "https://www.reasonstudios.com/reason/updates/release-notes")!
        case .logic: URL(string: "https://support.apple.com/en-us/109503")!
        case .live: URL(string: "https://www.ableton.com/en/release-notes/live-12/")!
        case .reaper: URL(string: "https://www.reaper.fm/download.php")!
        case .garageband: URL(string: "https://support.apple.com/en-us/109515")!
        }
    }
    public var dawDefinitionID: String? {
        switch self {
        case .reason: "reason"
        case .logic: "logic-pro"
        case .live: "ableton-live"
        case .reaper: "reaper"
        case .garageband: "garageband"
        case .d16, .kilohearts, .fabfilter, .tdrNova, .tdrKotelnikov, .tdrMolotok: nil
        }
    }
    var tdrProduct: String? {
        switch self { case .tdrNova: "Nova"; case .tdrKotelnikov: "Kotelnikov"; case .tdrMolotok: "Molotok"; default: nil }
    }
    var prefix: String {
        if self == .fabfilter { return "com.fabfilter." }
        if tdrProduct != nil { return "com.tokyodawnlabs." }
        return self == .d16 ? "com.d16group." : "com.kilohearts."
    }
}

public enum DirectVendorError: String, Error, LocalizedError {
    case response = "The official page could not be read safely."
    case layout = "The vendor page changed or its release information is ambiguous."
    case regression = "The vendor reports an older release. Previous evidence was retained."
    case notEnabled = "This source is not enabled in this build pending access review."
    public var errorDescription: String? { rawValue }
}

public struct DirectVendorObservation: Codable, Sendable {
    public let vendor: DirectVendor
    public let checkedAt: Date
    public let page: String
    public init(vendor: DirectVendor, checkedAt: Date, page: String) {
        self.vendor = vendor; self.checkedAt = checkedAt; self.page = page
    }
}

/// What survives a check: extracted release facts, never vendor page text.
public struct DirectVendorFacts: Codable, Sendable, Equatable {
    public var failedTokens: [String]? = nil
    public static let currentParserVersion = 3
    public let vendor: DirectVendor
    public let checkedAt: Date
    public let parserVersion: Int
    public let plugins: [PluginReleaseRecord]
    public let daws: [DAWReleaseRecord]
    public init(vendor: DirectVendor, checkedAt: Date, parserVersion: Int = DirectVendorFacts.currentParserVersion,
                plugins: [PluginReleaseRecord], daws: [DAWReleaseRecord] = []) {
        self.vendor = vendor; self.checkedAt = checkedAt; self.parserVersion = parserVersion
        self.plugins = plugins; self.daws = daws
    }
    public init(vendor: DirectVendor, checkedAt: Date, parserVersion: Int = DirectVendorFacts.currentParserVersion,
                plugins: [PluginReleaseRecord], daw: DAWReleaseRecord?) {
        self.init(vendor: vendor, checkedAt: checkedAt, parserVersion: parserVersion, plugins: plugins, daws: daw.map { [$0] } ?? [])
    }
}

public enum DirectVendorChecks {
    public static let maximumBytes = 2_000_000
    /// Facts for every source fit comfortably; anything larger is not a facts file.
    public static let maximumCacheBytes = 262_144
    /// Sent with every request so vendors can identify and contact the project.
    public static let userAgent: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let version = raw.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return "MKStudioUpkeep/\(version.isEmpty ? "dev" : version) (macOS; user-initiated update check; +https://github.com/mks-devx/MK-Studio-Upkeep)"
    }()
    /// Hosts the app may contact, for copy that must follow the data rather than name companies.
    public static var activeHosts: [String] {
        var seen: [String] = []
        for vendor in DirectVendor.active { if let host = vendor.url.host, !seen.contains(host) { seen.append(host) } }
        return seen
    }
    /// One host, or "a and b" when several sources are active.
    public static var activeHostsSentence: String {
        let hosts = activeHosts
        guard hosts.count > 1 else { return hosts.first ?? "no host" }
        return hosts.dropLast().joined(separator: ", ") + " and " + hosts.last!
    }
    public static var activeProductCount: Int {
        0
    }

    /// Consecutive requests to one host wait at least a second, or the host's declared crawl-delay.
    public static func politenessDelay(before vendor: DirectVendor, after previous: DirectVendor?) -> TimeInterval {
        guard let previous, previous.url.host == vendor.url.host, !vendor.isPublicAPI else { return 0 }
        return max(1, vendor.crawlDelay)
    }
    private static let version = #"[0-9]+(?:\.[0-9]+){1,3}"#

    private static func groups(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
        }
    }
    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func key(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// All known products for a source succeed together, or none acquire a new date.
    public static func records(from observation: DirectVendorObservation, baseline: [PluginReleaseRecord], now: Date = Date()) throws -> [PluginReleaseRecord] {
        guard observation.page.utf8.count <= maximumBytes,
              observation.checkedAt <= now, now.timeIntervalSince(observation.checkedAt) <= 30 * 86_400 else { throw DirectVendorError.response }
        guard observation.vendor.dawDefinitionID == nil else { throw DirectVendorError.layout }
        let vendor = observation.vendor
        if vendor == .fabfilter || vendor.tdrProduct != nil {
            return try expandedPluginRecords(from: observation, baseline: baseline)
        }
        var releases: [String: (String, URL?)] = [:]
        if vendor == .d16 {
            let blocks = groups(#"<h5\b[^>]*class="card-header"[^>]*>(.*?)</h5>(.*?)(?=<h5\b|\z)"#, observation.page)
            guard !blocks.isEmpty else { throw DirectVendorError.layout }
            for block in blocks {
                let heading = groups("^(.+?)\\s+(" + version + ")$", clean(block[0]))
                guard heading.count == 1 else { throw DirectVendorError.layout }
                let name = heading[0][0], number = heading[0][1]
                let links = groups(#"<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, block[1]).filter { clean($0[1]) == "Mac OS" }
                let expected = "https://cdn.d16.pl/installers/\(name.replacingOccurrences(of: " ", with: ""))/\(name.replacingOccurrences(of: " ", with: ""))-\(number).dmg"
                guard links.count == 1, links[0][0] == expected, releases[key(name)] == nil else { throw DirectVendorError.layout }
                releases[key(name)] = (number, URL(string: expected))
            }
        } else {
            guard clean(observation.page).contains("all have the same version number") else { throw DirectVendorError.layout }
            let labels = groups(#"<a\b[^>]*href="/data/install/_/mac"[^>]*>(.*?)</a>"#, observation.page)
            let headings = groups(#"<h3>\s*<a href="/changelog#("# + version + #")">"#, observation.page)
            guard labels.count == 1, let latest = headings.first?.first else { throw DirectVendorError.layout }
            let label = groups("^Kilohearts Installer\\s*(" + version + ") for Mac$", clean(labels[0][0]))
            guard label.count == 1, label[0][0] == latest else { throw DirectVendorError.layout }
            releases["shared"] = (latest, nil)
        }
        let known = baseline.filter { $0.vendorIdentifierPrefixes == [vendor.prefix] }
        guard !known.isEmpty else { throw DirectVendorError.layout }
        let date = ISO8601DateFormatter().string(from: observation.checkedAt).prefix(10)
        return try known.map { old in
            guard let release = releases[vendor == .kilohearts ? "shared" : key(old.productAliases[0])] else { throw DirectVendorError.layout }
            guard [.newer, .equal].contains(VersionComparator.compare(release.0, old.latestVersion)) else { throw DirectVendorError.regression }
            return PluginReleaseRecord(vendorIdentifierPrefixes: old.vendorIdentifierPrefixes, productAliases: old.productAliases,
                latestVersion: release.0, sourceURL: vendor.url, checkedOn: String(date), downloadURL: release.1)
        }
    }


    // Fixed product mappings: other editions and similarly named products never inherit evidence.
    private static func expandedPluginRecords(from observation: DirectVendorObservation, baseline: [PluginReleaseRecord]) throws -> [PluginReleaseRecord] {
        let vendor = observation.vendor
        let stems = ["Pro-Q 4": "proq4", "Pro-C 3": "proc3", "Pro-L 2": "prol2", "Pro-R 2": "pror2", "Pro-MB": "promb", "Pro-DS": "prods", "Pro-G": "prog", "Saturn 2": "saturn2", "Timeless 3": "timeless3", "Volcano 3": "volcano3", "Twin 3": "twin3", "One": "one", "Simplon": "simplon", "Micro": "micro"]
        let known = baseline.filter {
            $0.vendorIdentifierPrefixes == [vendor.prefix] &&
            (vendor == .fabfilter ? stems[$0.productAliases[0]] != nil : $0.productAliases[0] == "TDR \(vendor.tdrProduct ?? "")")
        }
        guard !known.isEmpty else { throw DirectVendorError.layout }
        return try known.map { old in
            let name = old.productAliases[0]
            let number: String
            if vendor == .fabfilter {
                let escaped = NSRegularExpression.escapedPattern(for: name)
                let blocks = groups("<h2\\b[^>]*>Download FabFilter " + escaped + #"</h2>(.*?)(?=<h2\b|\z)"#, observation.page)
                guard blocks.count == 1 else { throw DirectVendorError.layout }
                let versions = groups("<br\\s*/?>\\s*(" + version + ")\\s*&mdash;", blocks[0][0])
                guard versions.count == 1 else { throw DirectVendorError.layout }
                number = versions[0][0]
                // The product major is already part of the installer stem (proq4 + 13).
                let suffix = number.split(separator: ".").dropFirst().joined()
                let stem = stems[name]!
                let installerVersion = stem.last?.isNumber == true ? suffix : number.replacingOccurrences(of: ".", with: "")
                let expected = "https://cdn-b.fabfilter.com/downloads/ff\(stem)\(installerVersion).dmg"
                let links = groups(#"<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, blocks[0][0]).filter { clean($0[1]) == "Download for macOS" }
                guard links.count == 1, links[0][0] == expected else { throw DirectVendorError.layout }
            } else {
                let versions = groups("Latest version:\\s*<strong>(" + version + ")</strong>", observation.page)
                guard versions.count == 1, let product = vendor.tdrProduct else { throw DirectVendorError.layout }
                number = versions[0][0]
                let expected = "https://www.tokyodawn.net/labs/\(product)/\(number)/TDR \(product).zip"
                let links = groups(#"<a\b[^>]*href="([^"]+)"[^>]*title="([^"]+)"[^>]*>"#, observation.page).filter { $0[1] == "Download TDR \(product) - Mac Package" }
                guard links.count == 1, links[0][0] == expected else { throw DirectVendorError.layout }
            }
            guard [.equal, .newer].contains(VersionComparator.compare(number, old.latestVersion)) else { throw DirectVendorError.regression }
            return PluginReleaseRecord(vendorIdentifierPrefixes: old.vendorIdentifierPrefixes, productAliases: old.productAliases,
                latestVersion: number, sourceURL: vendor.url, checkedOn: EvidenceFreshness.day(observation.checkedAt))
        }
    }

    public static func logicRelease(from observation: DirectVendorObservation, baseline: DAWReleaseRecord? = nil, now: Date = Date()) throws -> DAWReleaseRecord {
        guard observation.vendor == .logic, observation.page.utf8.count <= maximumBytes,
              observation.checkedAt <= now, now.timeIntervalSince(observation.checkedAt) <= 30 * 86_400 else { throw DirectVendorError.response }
        let titles = groups(#"<h1\b[^>]*>(.*?)</h1>"#, observation.page).map { clean($0[0]) }
        let text = clean(observation.page)
        guard titles == ["Logic Pro for Mac release notes"],
              text.contains("These release notes apply to both the one-time purchase and Apple Creator Studio versions of Logic Pro for Mac.") else { throw DirectVendorError.layout }
        let headings = groups(#"<h2\b[^>]*>(.*?)</h2>"#, observation.page).map { clean($0[0]) }
        guard let first = headings.first else { throw DirectVendorError.layout }
        let latest = groups("^New in Logic Pro(?: for Mac)? (" + version + ")$", first)
        guard latest.count == 1,
              headings.filter({ $0.hasPrefix("New in Logic Pro") }).count == 1 else { throw DirectVendorError.layout }
        let number = latest[0][0]
        if let baseline, ![.equal, .newer].contains(VersionComparator.compare(number, baseline.latestVersion)) {
            throw DirectVendorError.regression
        }
        return DAWReleaseRecord(definitionID: "logic-pro", latestVersion: number, sourceURL: DirectVendor.logic.url,
            checkedOn: EvidenceFreshness.day(observation.checkedAt))
    }

    public static func dawRelease(from observation: DirectVendorObservation, baseline: DAWReleaseRecord? = nil, now: Date = Date()) throws -> DAWReleaseRecord {
        if observation.vendor == .logic { return try logicRelease(from: observation, baseline: baseline, now: now) }
        guard let id = observation.vendor.dawDefinitionID, observation.page.utf8.count <= maximumBytes,
              observation.checkedAt <= now, now.timeIntervalSince(observation.checkedAt) <= 30 * 86_400 else { throw DirectVendorError.response }
        let page = observation.page
        let titles = groups(#"<h1\b[^>]*>(.*?)</h1>"#, page).map { clean($0[0]) }
        var candidates: [[String]] = []
        switch observation.vendor {
        case .reason:
            let headers = groups(#"<h3\b[^>]*>(.*?)</h3>"#, page).map { clean($0[0]) }
            candidates = headers.flatMap { groups("^Reason (14\\.[0-9]+\\.[0-9]+) Release Notes$", $0) }
            guard headers.first == candidates.first.map({ "Reason \($0[0]) Release Notes" }) else { throw DirectVendorError.layout }
        case .live:
            guard titles.contains("Live 12 Release Notes") else { throw DirectVendorError.layout }
            let headers = groups(#"<h2\b[^>]*>(.*?)</h2>"#, page).map { clean($0[0]) }
            candidates = headers.flatMap { groups("^(12\\.[0-9]+(?:\\.[0-9]+)?) Release Notes$", $0) }
        case .garageband:
            guard titles == ["GarageBand for macOS release notes"] else { throw DirectVendorError.layout }
            let headers = groups(#"<h2\b[^>]*>(.*?)</h2>"#, page).map { clean($0[0]) }
            guard let first = headers.first else { throw DirectVendorError.layout }
            candidates = groups("^New in GarageBand (" + version + ")$", first)
            guard candidates.count == 1 else { throw DirectVendorError.layout }
        case .reaper:
            guard titles.contains("Download and Evaluate REAPER for Free"), clean(page).contains("macOS") else { throw DirectVendorError.layout }
            let labels = groups(#"<div\b[^>]*class=['"]hdrbottom['"][^>]*>(.*?)</div>"#, page)
            candidates = labels.flatMap { groups("^Version (" + version + "): .+$", clean($0[0])) }
            guard candidates.count == 1 else { throw DirectVendorError.layout }
            let number = candidates[0][0]
            let major = number.split(separator: ".")[0]
            let expected = "files/\(major).x/reaper\(number.replacingOccurrences(of: ".", with: ""))_universal.dmg"
            guard groups(#"href=['"]([^'"]+)['"]"#, page).contains(where: { $0[0] == expected }) else { throw DirectVendorError.layout }
        default: throw DirectVendorError.layout
        }
        guard let number = candidates.first?.first else { throw DirectVendorError.layout }
        // A rearranged list must not silently pick an older release.
        guard candidates.allSatisfy({ [.equal, .newer].contains(VersionComparator.compare(number, $0[0])) }) else { throw DirectVendorError.layout }
        if let baseline, ![.equal, .newer].contains(VersionComparator.compare(number, baseline.latestVersion)) { throw DirectVendorError.regression }
        return DAWReleaseRecord(definitionID: id, latestVersion: number, sourceURL: observation.vendor.url,
            checkedOn: EvidenceFreshness.day(observation.checkedAt), majorVersion: observation.vendor == .live ? 12 : observation.vendor == .reason ? 14 : nil)
    }

    public static func overlay(_ observations: [DirectVendorObservation], baseline: [PluginReleaseRecord], now: Date = Date()) -> [PluginReleaseRecord] {
        let facts = DirectVendor.allCases.compactMap { vendor -> DirectVendorFacts? in
            guard let observation = observations.filter({ $0.vendor == vendor }).max(by: { $0.checkedAt < $1.checkedAt }) else { return nil }
            return try? self.facts(from: observation, baseline: baseline, dawBaseline: nil, now: now)
        }
        return overlay(facts, baseline: baseline, now: now)
    }

    /// Parses once, then discards the page. Throws exactly like the underlying reader.
    public static func facts(from observation: DirectVendorObservation, baseline: [PluginReleaseRecord],
                             dawBaseline: DAWReleaseRecord?, now: Date = Date()) throws -> DirectVendorFacts {
        if observation.vendor.dawDefinitionID != nil {
            let release = try dawRelease(from: observation, baseline: dawBaseline, now: now)
            return DirectVendorFacts(vendor: observation.vendor, checkedAt: observation.checkedAt, plugins: [], daws: [release])
        }
        let releases = try records(from: observation, baseline: baseline, now: now)
        return DirectVendorFacts(vendor: observation.vendor, checkedAt: observation.checkedAt, plugins: releases, daws: [])
    }

    private static func isUsable(_ facts: DirectVendorFacts, now: Date) -> Bool {
        facts.parserVersion == DirectVendorFacts.currentParserVersion
            && facts.checkedAt <= now && now.timeIntervalSince(facts.checkedAt) <= 30 * 86_400
    }

    /// A source's facts apply all together or not at all; a regression against a newer
    /// baseline (for example a fresher signed catalogue) keeps the baseline for that source.
    public static func overlay(_ facts: [DirectVendorFacts], baseline: [PluginReleaseRecord], now: Date = Date()) -> [PluginReleaseRecord] {
        var records = baseline
        for vendor in DirectVendor.allCases {
            guard let current = facts.filter({ $0.vendor == vendor }).max(by: { $0.checkedAt < $1.checkedAt }),
                  isUsable(current, now: now), !current.plugins.isEmpty else { continue }
            let baseByID = Dictionary(baseline.map { ($0.catalogueID, $0) }, uniquingKeysWith: { first, _ in first })
            let applicable = current.plugins.filter { baseByID[$0.catalogueID] != nil }
            guard !applicable.isEmpty, applicable.allSatisfy({ update in
                [.equal, .newer].contains(VersionComparator.compare(update.latestVersion, baseByID[update.catalogueID]!.latestVersion))
            }) else { continue }
            let byID = Dictionary(applicable.map { ($0.catalogueID, $0) }, uniquingKeysWith: { first, _ in first })
            // Facts may move the version, its date and its download link. Identity, aliases, the
            // official page and edition links always stay with the signed catalogue record.
            records = records.map { base in
                guard let update = byID[base.catalogueID] else { return base }
                var merged = PluginReleaseRecord(vendorIdentifierPrefixes: base.vendorIdentifierPrefixes, productAliases: base.productAliases,
                    latestVersion: update.latestVersion, sourceURL: base.sourceURL, checkedOn: update.checkedOn,
                    downloadURL: update.downloadURL, family: base.family, edition: base.edition)
                merged.checkMethod = nil
                return merged
            }
        }
        return records
    }

    public static func dawRelease(from facts: DirectVendorFacts, baseline: DAWReleaseRecord?, now: Date = Date()) -> DAWReleaseRecord? {
        dawReleases(from: facts, baseline: baseline.map { [$0] } ?? [], now: now).first
    }
    /// Fresh DAW facts that do not regress against the given baseline records.
    public static func dawReleases(from facts: DirectVendorFacts, baseline: [DAWReleaseRecord], now: Date = Date()) -> [DAWReleaseRecord] {
        guard isUsable(facts, now: now) else { return [] }
        return facts.daws.filter { release in
            if release.definitionID != facts.vendor.dawDefinitionID { return false }
            if let base = baseline.first(where: { $0.definitionID == release.definitionID }),
               ![.equal, .newer].contains(VersionComparator.compare(release.latestVersion, base.latestVersion)) { return false }
            return true
        }.map { release in
            var value = release
            value.checkMethod = nil
            return value
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: VendorRedirectBlocker(), delegateQueue: nil)
    }

    public static func fetch(_ vendor: DirectVendor) async throws -> DirectVendorObservation {
        try Task.checkCancellation()
        guard vendor.isActive else { throw DirectVendorError.notEnabled }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: VendorRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: vendor.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == vendor.url,
              http.mimeType == "text/html", http.expectedContentLength <= maximumBytes else { throw DirectVendorError.response }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw DirectVendorError.response }
            data.append(byte)
        }
        guard let page = String(data: data, encoding: .utf8) else { throw DirectVendorError.response }
        return .init(vendor: vendor, checkedAt: Date(), page: page)
    }

    /// The cache holds extracted facts for active sources only: versions, official URLs and
    /// dates. It never contains vendor page text, installed product names or local paths.
    public static func loadCache(_ url: URL) -> [DirectVendorFacts] {
        guard let data = SafeFileAccess.data(at: url, maximumBytes: maximumCacheBytes), JSONDepth.isWithinLimit(data),
              let values = try? JSONDecoder().decode([DirectVendorFacts].self, from: data),
              validCacheEntries(values) else { return [] }
        return values.filter { $0.vendor.isActive }
    }
    public static func saveCache(_ values: [DirectVendorFacts], to url: URL) throws {
        guard validCacheEntries(values) else { throw DirectVendorError.response }
        let data = try JSONEncoder().encode(values)
        guard data.count <= maximumCacheBytes else { throw DirectVendorError.response }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    static func validCacheEntries(_ values: [DirectVendorFacts]) -> Bool {
        guard values.count <= DirectVendor.allCases.count, Set(values.map(\.vendor)).count == values.count else { return false }
        return values.allSatisfy { facts in
            guard facts.parserVersion == DirectVendorFacts.currentParserVersion, facts.plugins.count <= 200, facts.daws.count <= 50 else { return false }
            let dawsValid = facts.daws.allSatisfy { daw in
                let identityOK = daw.definitionID == facts.vendor.dawDefinitionID && facts.plugins.isEmpty
                let urlOK = daw.sourceURL == facts.vendor.url
                return identityOK && urlOK && EvidenceFreshness.date(daw.checkedOn) != nil && VersionComparator.parse(daw.latestVersion)?.channel == .stable
            }
            guard dawsValid, Set(facts.daws.map(\.definitionID)).count == facts.daws.count,
                  facts.vendor.dawDefinitionID == nil || facts.plugins.isEmpty,
                  Set(facts.plugins.map(\.catalogueID)).count == facts.plugins.count else { return false }
            return facts.plugins.allSatisfy { record in
                let prefixOK = record.vendorIdentifierPrefixes == [facts.vendor.prefix]
                let urlOK = record.sourceURL == facts.vendor.url
                return prefixOK && urlOK
                    && !record.productAliases.isEmpty && record.productAliases.allSatisfy { !$0.isEmpty && $0.count <= 80 }
                    && EvidenceFreshness.date(record.checkedOn) != nil
                    && VersionComparator.parse(record.latestVersion)?.channel == .stable
                    && (record.downloadURL.map { PluginDownloadPolicy.isAllowed($0, for: record) } ?? true)
            }
        }
    }
}

private final class VendorRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
