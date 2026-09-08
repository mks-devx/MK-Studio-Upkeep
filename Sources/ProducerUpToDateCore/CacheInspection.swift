// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Inspection only. No file contents, cleanup plans or deletion APIs are involved.
public enum CacheInspection {
    public struct Location: Identifiable, Sendable {
        public var id: String { path.path }
        public let name: String
        public let path: URL
        public let evidence: String
    }
    public struct Entry: Identifiable, Sendable {
        public var id: String { location.id }
        public let location: Location
        public let measurement: StorageMeasurement.Result
    }
    public struct Report: Sendable {
        public let entries: [Entry]
        public let skipped: Int
        public let checkedAt: Date
    }
    public static func locations(daws: [InstalledDAWRecord], home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                 systemCaches: URL = URL(fileURLWithPath: "/Library/Caches")) -> [Location] {
        let userCaches = home.appendingPathComponent("Library/Caches")
        // Documented by audio vendors as shared AU scan data, never assigned to one product.
        var locations = [Location(name: "Shared Audio Unit cache", path: userCaches.appendingPathComponent("AudioUnitCache"),
                                  evidence: "Documented Audio Unit scan-cache location; shared across audio software.")]
        for daw in daws where !daw.identityIsInferred {
            guard let id = daw.bundleIdentifier, validIdentifier(id) else { continue }
            for root in [userCaches, systemCaches] {
                locations.append(Location(name: DisplaySanitiser.sanitise(daw.name) ?? "DAW cache",
                    path: root.appendingPathComponent(id),
                    evidence: "Standard cache folder with an exact recognised DAW bundle identifier. Contents and exclusive ownership are not verified."))
            }
        }
        for daw in daws where !daw.identityIsInferred {
            if daw.bundleIdentifier == "com.bitwig.BitwigStudio" {
                locations.append(Location(name: "Bitwig Studio · plugin index",
                    path: home.appendingPathComponent("Library/Application Support/Bitwig/Bitwig Studio/index"),
                    evidence: "Vendor-documented plugin index. Rebuilding it requires another scan. Inspection only."))
            }
            if daw.bundleIdentifier == "se.propellerheads.reason" {
                locations.append(Location(name: "Reason · plugin cache",
                    path: home.appendingPathComponent("Library/Application Support/Propellerhead Software/Reason/Caches"),
                    evidence: "Location documented for Reason 12; other releases may use different locations. Inspection only."))
            }
        }
        var seen = Set<String>()
        return locations.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
    }
    private static func validIdentifier(_ id: String) -> Bool {
        id.count <= 255 && id.contains(".") && !id.hasPrefix(".") && !id.hasSuffix(".") && !id.contains("..") &&
        id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .-").contains($0) }
    }
    public static func inspect(_ locations: [Location], limit: Int = 100_000) throws -> Report {
        var entries: [Entry] = []
        var skipped = 0
        var remaining = max(0, limit)
        for location in locations {
            try Task.checkCancellation()
            let path = location.path
            guard path.isFileURL, path.standardizedFileURL.path == path.resolvingSymlinksInPath().path else { skipped += 1; continue }
            let info: [FileAttributeKey: Any]
            do { info = try FileManager.default.attributesOfItem(atPath: path.path) }
            catch {
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain || error.code != NSFileReadNoSuchFileError { skipped += 1 }
                continue
            }
            guard info[.type] as? FileAttributeType == .typeDirectory else { skipped += 1; continue }
            guard remaining > 0 else { skipped += 1; continue }
            let measured = try StorageMeasurement.measure([path], limit: remaining)
            remaining -= measured.inspectedEntries
            entries.append(Entry(location: location, measurement: measured))
        }
        return Report(entries: entries, skipped: skipped, checkedAt: Date())
    }
}
