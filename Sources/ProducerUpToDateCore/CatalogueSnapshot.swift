// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation

public struct CatalogueSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let sequence: Int
    public let generatedOn: String
    public let plugins: [PluginReleaseRecord]
    public let daws: [DAWReleaseRecord]
    public let drivers: [DriverReleaseRecord]
    public let architectures: [ArchitectureSupportRecord]
    public let releaseNotes: [ReviewedReleaseNotes]
}

public enum CatalogueError: String, Error, LocalizedError {
    case missing = "No catalogue was supplied. Products remain not checked."
    case invalidSignature = "The catalogue signature could not be verified."
    case invalidData = "The catalogue contains unsupported or invalid evidence."
    case rollback = "An older or conflicting catalogue was rejected."
    case network = "The catalogue could not be downloaded. The last valid snapshot is retained."
    public var errorDescription: String? { rawValue }
}

public struct SignedCatalogueEnvelope: Codable, Sendable {
    public let payload: Data
    public let signature: Data
    public init(payload: Data, signature: Data) { self.payload = payload; self.signature = signature }
}

public enum CatalogueValidator {
    public static let maximumBytes = 4_194_304
    public static let officialHosts: Set<String> = ["www.fabfilter.com", "www.ableton.com", "www.bitwig.com", "downloads.bitwig.com", "thehouseofkush.com", "support.izotope.com", "support.antelopeaudio.com", "www.tokyodawn.net", "kilohearts.com", "d16.pl", "tal-software.com", "valhalladsp.com", "www.voxengo.com", "support.apple.com", "www.reaper.fm", "www.reasonstudios.com"]

    public static func verify(_ data: Data, publicKey: Data, minimumSequence: Int = 1,
                              now: Date = Date()) throws -> CatalogueSnapshot {
        guard data.count <= maximumBytes, JSONDepth.isWithinLimit(data),
              let envelope = try? JSONDecoder().decode(SignedCatalogueEnvelope.self, from: data),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(envelope.signature, for: envelope.payload) else { throw CatalogueError.invalidSignature }
        guard JSONDepth.isWithinLimit(envelope.payload),
              let snapshot = try? JSONDecoder().decode(CatalogueSnapshot.self, from: envelope.payload) else { throw CatalogueError.invalidData }
        try validate(snapshot, now: now)
        guard snapshot.sequence >= minimumSequence else { throw CatalogueError.rollback }
        return snapshot
    }

    public static func validate(_ snapshot: CatalogueSnapshot, now: Date = Date()) throws {
        guard snapshot.schemaVersion == 1, snapshot.sequence > 0,
              validDate(snapshot.generatedOn, now: now),
              snapshot.plugins.count + snapshot.daws.count + snapshot.architectures.count + snapshot.drivers.count <= 10_000,
              snapshot.releaseNotes.count <= 50_000 else { throw CatalogueError.invalidData }
        var productIDs = Set<String>()
        var aliasKeys = Set<String>()
        var familyEditions: [String: (prefixes: [String], editions: Set<Int>)] = [:]
        for record in snapshot.plugins {
            guard !record.vendorIdentifierPrefixes.isEmpty, !record.productAliases.isEmpty,
                  record.vendorIdentifierPrefixes.allSatisfy(validPrefix),
                  record.productAliases.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 120 }),
                  productIDs.insert(record.catalogueID).inserted,
                  validRelease(record.latestVersion, record.sourceURL, record.checkedOn, now),
                  record.downloadURL.map({ PluginDownloadPolicy.isAllowed($0, for: record) }) ?? true else { throw CatalogueError.invalidData }
            // Editions: both fields or neither; the edition is the major line of its own release;
            // one vendor line per family; no two records may claim the same edition.
            switch (record.family, record.edition) {
            case (nil, nil): break
            case let (family?, edition?):
                guard !family.trimmingCharacters(in: .whitespaces).isEmpty, family.count <= 80, edition > 0,
                      edition == VersionComparator.parse(record.latestVersion)?.numbers.first else { throw CatalogueError.invalidData }
                var entry = familyEditions[family] ?? (record.vendorIdentifierPrefixes, [])
                guard entry.prefixes == record.vendorIdentifierPrefixes, entry.editions.insert(edition).inserted else { throw CatalogueError.invalidData }
                familyEditions[family] = entry
            default: throw CatalogueError.invalidData
            }
            for prefix in record.vendorIdentifierPrefixes {
                for alias in record.productAliases {
                    let key = prefix.lowercased() + alias.lowercased().filter { $0.isLetter || $0.isNumber }
                    guard aliasKeys.insert(key).inserted else { throw CatalogueError.invalidData }
                }
            }
        }
        for record in snapshot.daws {
            guard !record.definitionID.isEmpty, record.definitionID.count <= 120, productIDs.insert(record.definitionID).inserted,
                  record.majorVersion.map({ $0 > 0 && $0 == VersionComparator.parse(record.latestVersion)?.numbers.first }) ?? true,
                  validRelease(record.latestVersion, record.sourceURL, record.checkedOn, now) else { throw CatalogueError.invalidData }
        }
        var driverIDs = Set<String>()
        for record in snapshot.drivers {
            guard !record.bundleIdentifier.isEmpty, record.bundleIdentifier.count <= 200, driverIDs.insert(record.bundleIdentifier).inserted,
                  validRelease(record.latestVersion, record.sourceURL, record.checkedOn, now) else { throw CatalogueError.invalidData }
        }
        for record in snapshot.architectures {
            guard !record.vendorIdentifierPrefixes.isEmpty, record.vendorIdentifierPrefixes.allSatisfy(validPrefix),
                  !(record.exactProductAliases + record.productNamePrefixes).isEmpty,
                  !(record.exactProductAliases + record.productNamePrefixes).contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.count > 120 }),
                  !record.nativeFormats.isEmpty,
                  validRelease(record.minimumNativeVersion, record.sourceURL, record.checkedOn, now),
                  [.older, .equal].contains(VersionComparator.compare(record.minimumNativeVersion, record.recommendedVersion)) else { throw CatalogueError.invalidData }
        }
        var noteIDs = Set<String>()
        for note in snapshot.releaseNotes {
            guard productIDs.contains(note.productID), noteIDs.insert(note.id).inserted,
                  validRelease(note.version, note.sourceURL, note.checkedOn, now),
                  note.releaseDate.map({ validDate($0, now: now) && $0 <= note.checkedOn }) ?? true,
                  note.highlights.count <= 12, note.highlights.allSatisfy({ !$0.isEmpty && $0.count <= 500 }),
                  (note.criticalReason ?? "").count <= 500,
                  note.importance != .critical || !(note.criticalReason ?? "").isEmpty else { throw CatalogueError.invalidData }
            let latest = snapshot.plugins.first { $0.catalogueID == note.productID }?.latestVersion
                ?? snapshot.daws.first { $0.definitionID == note.productID }?.latestVersion ?? ""
            guard [.older, .equal].contains(VersionComparator.compare(note.version, latest)) else { throw CatalogueError.invalidData }
        }
    }

    private static func validPrefix(_ value: String) -> Bool {
        value.count > 4 && value.count <= 120 && value.hasSuffix(".") && !value.contains("..")
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }
    private static func validDate(_ value: String, now: Date) -> Bool {
        guard let date = EvidenceFreshness.date(value) else { return false }; return date <= now
    }
    /// The only kind of link the app follows from data: https to a reviewed official host, with
    /// no credentials or port. Applied to signed records and to the locally cached facts alike.
    public static func isOfficialLink(_ url: URL) -> Bool {
        url.scheme == "https" && officialHosts.contains(url.host ?? "")
            && url.user == nil && url.password == nil && url.port == nil
    }
    private static func validRelease(_ version: String, _ url: URL, _ date: String, _ now: Date) -> Bool {
        VersionComparator.parse(version)?.channel == .stable && version.count <= 64 && validDate(date, now: now)
            && isOfficialLink(url)
    }
}

/// Transport and cache are independent of scanning. Clients supply an approved endpoint.
/// No service or catalogue is configured by the app; experiments must provide explicit input.
public actor CatalogueStore {
    private let publicKey: Data
    private let cacheURL: URL
    private var acceptedData: Data
    public private(set) var snapshot: CatalogueSnapshot
    public private(set) var lastFailure: String?

    public init(bundledData: Data, publicKey: Data, cacheURL: URL, now: Date = Date()) throws {
        self.publicKey = publicKey; self.cacheURL = cacheURL
        let bundled = try CatalogueValidator.verify(bundledData, publicKey: publicKey, now: now)
        self.snapshot = bundled; self.acceptedData = bundledData
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            do {
                guard let cached = SafeFileAccess.data(at: cacheURL) else { throw CatalogueError.invalidData }
                let validated = try CatalogueValidator.verify(cached, publicKey: publicKey, minimumSequence: bundled.sequence, now: now)
                // Same sequence with different bytes is a conflict, not a refresh.
                guard validated.sequence > bundled.sequence || cached == bundledData else { throw CatalogueError.invalidData }
                self.snapshot = validated; self.acceptedData = cached
            } catch CatalogueError.rollback {
                // The supplied baseline is newer than the cache: replace the stale cache quietly.
                try? bundledData.write(to: cacheURL, options: .atomic)
            } catch {
                self.lastFailure = "Cached catalogue rejected; using the supplied baseline."
            }
        }
    }

    public func accept(_ data: Data, now: Date = Date()) throws {
        do {
            let next = try CatalogueValidator.verify(data, publicKey: publicKey, minimumSequence: snapshot.sequence, now: now)
            guard next.sequence > snapshot.sequence || data == acceptedData else { throw CatalogueError.rollback }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: .atomic)
            acceptedData = data; snapshot = next; lastFailure = nil
        } catch { lastFailure = error.localizedDescription; throw error }
    }

    public func refresh(from endpoint: URL, now: Date = Date()) async throws {
        guard CatalogueRefreshPolicy.endpoint(endpoint.absoluteString) != nil else { throw CatalogueError.network }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: CatalogueRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: endpoint)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("MK-Studio-Upkeep", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https", response.url?.host == endpoint.host,
                  response.mimeType == "application/json",
                  response.expectedContentLength <= Int64(CatalogueValidator.maximumBytes) else { throw CatalogueError.network }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < CatalogueValidator.maximumBytes else { throw CatalogueError.invalidData }
                data.append(byte)
            }
            try accept(data, now: now)
        } catch { lastFailure = error.localizedDescription; throw error }
    }
}

private final class CatalogueRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
