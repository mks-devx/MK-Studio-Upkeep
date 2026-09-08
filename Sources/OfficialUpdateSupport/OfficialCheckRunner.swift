// SPDX-License-Identifier: MPL-2.0
import Foundation
import ProducerUpToDateCore
import UpdateEnginePrototypeSupport

public struct OfficialTarget: Sendable, Identifiable {
    public let id: String
    public let productID: String
    public let label: String
    public let path: URL
    public let identifier: String?
    public let installed: String?
    public let entry: OfficialSource?
    public let reason: String?

    public static func discover(products: [NormalizedPluginProduct], daws: [InstalledDAWRecord], directory: OfficialSourceDirectory) -> [Self] {
        var targets = products.flatMap { product in
            PluginBundleRecord.distinctInstalledCopies(product.bundles).map { bundle in
                make(productID: "plugin:" + product.id, label: bundle.format.rawValue + " · " + bundle.path.lastPathComponent,
                     path: bundle.path, identifier: bundle.bundleIdentifier, name: bundle.name, installed: bundle.displayVersion,
                     kind: .plugin, excluded: false, directory: directory)
            }
        }
        targets += daws.map { daw in
            make(productID: "daw:" + daw.id, label: daw.name + " · " + daw.path.lastPathComponent,
                 path: daw.path, identifier: daw.bundleIdentifier, name: daw.name, installed: daw.displayVersion,
                 kind: .daw, excluded: daw.identityIsInferred || daw.installedFromAppStore, directory: directory)
        }
        return targets
    }
    private static func make(productID: String, label: String, path: URL, identifier: String?, name: String, installed: String?, kind: OfficialProductKind, excluded: Bool, directory: OfficialSourceDirectory) -> Self {
        let entry = excluded ? nil : directory.match(identifier: identifier, name: name, version: installed, kind: kind)
        let recognisedID = directory.entries.contains { $0.kind == kind && $0.identifiers.contains(identifier ?? "") }
        return .init(id: productID + "|" + path.standardizedFileURL.path, productID: productID,
                     label: DisplaySanitiser.sanitise(label) ?? "Installed copy", path: path, identifier: identifier,
                     installed: installed, entry: entry,
                     reason: excluded ? "Use the vendor app or App Store for this installation." : entry != nil ? nil : recognisedID ? "Edition, name or installed version needs review." : "Automatic detection is not supported for this copy yet.")
    }
    /// Re-read locally just before a request. Changed metadata requires a new scan.
    func unchanged() -> Bool {
        let info = path.appendingPathComponent("Contents/Info.plist")
        guard SafeFileAccess.contained(info, in: path), let data = SafeFileAccess.data(at: info, maximumBytes: 1_048_576),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return false }
        return plist["CFBundleIdentifier"] as? String == identifier && plist["CFBundleShortVersionString"] as? String == installed
    }
}

public enum OfficialResultState: String, Sendable {
    case update = "Update available"
    case matched = "Matches official release"
    case ahead = "Installed version is newer than the source"
    case ambiguous = "Could not compare"
    case failed = "Check failed"
    case stale = "Check expired"
}
public struct OfficialObservation: Sendable {
    public let copyID: String
    public let entry: OfficialSource
    public let installed: String?
    public let latest: String?
    public let checkedAt: Date
    public var failure: String? = nil
    public func state(at now: Date) -> OfficialResultState {
        let age = now.timeIntervalSince(checkedAt)
        guard age >= 0, age < 86_400 else { return .stale }
        if failure != nil { return .failed }
        guard let installed, let latest,
              let left = VersionComparator.parse(installed), let right = VersionComparator.parse(latest),
              left.channel == .stable, right.channel == .stable,
              left.numbers.first == entry.major, right.numbers.first == entry.major else { return .ambiguous }
        switch VersionComparator.compare(installed, latest) {
        case .older: return .update
        case .equal: return .matched
        case .newer: return .ahead
        case .incomparable: return .ambiguous
        }
    }
}
public enum OfficialCheckRunner {
    public static func check(_ targets: [OfficialTarget], allowNetwork: Bool,
                             fetch: @Sendable (URL) throws -> Data = { try PublicFeedTransport.fetch($0, allowNetwork: true, html: true) }) throws -> [OfficialObservation] {
        guard allowNetwork else { throw OfficialCheckError.permission }
        var pages: [URL: Result<Data, OfficialCheckError>] = [:]
        var observations: [OfficialObservation] = []
        for target in targets {
            try Task.checkCancellation()
            guard let entry = target.entry else { continue }
            var result = OfficialObservation(copyID: target.id, entry: entry, installed: target.installed, latest: nil, checkedAt: Date())
            guard target.unchanged() else {
                result.failure = "Installed files changed or could not be read. Scan again."
                observations.append(result); continue
            }
            if pages[entry.source] == nil {
                guard pages.count < 8 else { throw OfficialCheckError.directory }
                do { pages[entry.source] = .success(try fetch(entry.source)) }
                catch is CancellationError { throw CancellationError() }
                catch { pages[entry.source] = .failure(.network) }
            }
            do {
                let version = try OfficialReleaseParser.version(pages[entry.source]!.get(), entry: entry)
                guard target.unchanged() else {
                    result.failure = "Installed files changed during the check. Scan again."
                    observations.append(result); continue
                }
                result = .init(copyID: target.id, entry: entry, installed: target.installed, latest: version, checkedAt: Date())
            } catch { result.failure = (error as? OfficialCheckError)?.rawValue ?? OfficialCheckError.ambiguous.rawValue }
            observations.append(result)
        }
        return observations
    }
}
