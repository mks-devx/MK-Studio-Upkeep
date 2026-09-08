// SPDX-License-Identifier: MPL-2.0
import Foundation
import ProducerUpToDateCore

public struct FeedTarget: Sendable {
    public let productID: String
    public let name: String
    public let copy: String
    public let build: String?
    public let source: URL?
    public let unavailableReason: String?

    public init(productID: String, name: String, copy: String, build: String?, source: URL?, unavailableReason: String? = nil) {
        self.productID = productID; self.name = name; self.copy = copy
        self.build = build; self.source = source; self.unavailableReason = unavailableReason
    }

    public static func discover(in scan: StudioScanResult) -> [Self] {
        var targets = scan.products.flatMap { product in
            PluginBundleRecord.distinctInstalledCopies(product.bundles).map { record in
                make(productID: "plugin:" + product.id, name: product.name,
                     copy: record.format.rawValue + " · " + record.path.lastPathComponent,
                     path: record.path, build: record.buildVersion, identifier: record.bundleIdentifier,
                     identityUncertain: product.requiresVerification, appStore: false)
            }
        }
        targets += scan.daws.map { daw in
            make(productID: "daw:" + daw.id, name: daw.name, copy: daw.path.lastPathComponent,
                 path: daw.path, build: daw.buildVersion, identifier: daw.bundleIdentifier,
                 identityUncertain: daw.identityIsInferred, appStore: daw.installedFromAppStore)
        }
        return targets
    }

    private static func make(productID: String, name: String, copy: String, path: URL, build: String?, identifier: String?, identityUncertain: Bool, appStore: Bool) -> Self {
        func target(_ source: URL? = nil, _ reason: String? = nil) -> Self {
            Self(productID: productID, name: name, copy: copy, build: build, source: source, unavailableReason: reason)
        }
        let info = path.appendingPathComponent("Contents/Info.plist")
        guard SafeFileAccess.contained(info, in: path), let data = SafeFileAccess.data(at: info, maximumBytes: 1_048_576),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return target(nil, "Bundle metadata unavailable")
        }
        guard let raw = plist["SUFeedURL"] as? String else { return target(nil, "No declared update feed") }
        guard let link = DeclaredProductLink(kind: .updateFeed, value: raw), PublicFeedTransport.acceptedURL(link.url) else {
            return target(nil, "Unsupported feed address")
        }
        if appStore { return target(link.url, "Use the App Store for this installation") }
        if identityUncertain || identifier == nil { return target(link.url, "Product identity needs review") }
        if plist["CFBundleIdentifier"] as? String != identifier || plist["CFBundleVersion"] as? String != build {
            return target(link.url, "Installed metadata changed during discovery")
        }
        if plist["SURequireSignedFeed"] as? Bool == true { return target(link.url, "Signed feed verification is not implemented") }
        guard let build, VersionComparator.parse(build)?.channel == .stable else { return target(link.url, "Missing or unsupported installed build") }
        return target(link.url)
    }
}

public struct FeedCoveragePlan: Sendable {
    public let targets: [FeedTarget]
    public var productCount: Int { Set(targets.map(\.productID)).count }
    public var eligible: [FeedTarget] { targets.filter { $0.source != nil && $0.unavailableReason == nil } }
    public var eligibleProductCount: Int { Set(eligible.map(\.productID)).count }
    public var declaredProductCount: Int { Set(targets.filter { $0.source != nil }.map(\.productID)).count }
    public init(targets: [FeedTarget]) {
        let owners = Dictionary(grouping: targets.filter { $0.source != nil }, by: { $0.source! })
            .mapValues { Set($0.map(\.productID)) }
        self.targets = targets.map { target in
            var reason = target.unavailableReason
            if let url = target.source, (owners[url]?.count ?? 0) > 1 { reason = "Feed is shared by different products; mapping needs review" }
            if let url = target.source, !PublicFeedTransport.acceptedURL(url) { reason = "Unsupported feed address" }
            if target.source == nil && reason == nil { reason = "No declared update feed" }
            if target.build.flatMap({ VersionComparator.parse($0) })?.channel != .stable, reason == nil { reason = "Missing or unsupported installed build" }
            return FeedTarget(productID: target.productID, name: target.name, copy: target.copy,
                              build: target.build, source: target.source, unavailableReason: reason)
        }
    }
}

public struct FeedCheckObservation: Sendable {
    public let target: FeedTarget
    public let result: FeedComparison?
    public let failure: String?
}

public enum FeedCheckRunner {
    /// Explicit permission gates all DNS and HTTP. One fetch per source per run;
    /// every installed copy is compared separately. No facts are persisted yet.
    public static func check(_ plan: FeedCoveragePlan, allowNetwork: Bool, macOS: String,
                             appleSilicon: Bool, maximumSources: Int = 32,
                             fetch: @Sendable (URL) throws -> Data = { try PublicFeedTransport.fetch($0, allowNetwork: true) }) throws -> [FeedCheckObservation] {
        guard allowNetwork else { throw FeedFailure.network }
        guard (1...32).contains(maximumSources) else { throw FeedFailure.unsupported }
        var sources: [URL: Result<[FeedRelease], FeedFailure>] = [:]
        var observations: [FeedCheckObservation] = []
        for target in plan.targets {
            try Task.checkCancellation()
            guard let url = target.source, target.unavailableReason == nil else {
                observations.append(.init(target: target, result: nil, failure: target.unavailableReason ?? "No declared update feed")); continue
            }
            if sources[url] == nil {
                guard sources.count < maximumSources else {
                    observations.append(.init(target: target, result: nil, failure: "Prototype source limit reached")); continue
                }
                do { sources[url] = .success(try SparkleFeed.parse(fetch(url))) }
                catch is CancellationError { throw CancellationError() }
                catch let error as FeedFailure { sources[url] = .failure(error) }
                catch { sources[url] = .failure(.network) }
            }
            do {
                let releases = try sources[url]!.get()
                let result = try FeedComparison.evaluate(releases, installedBuild: target.build,
                    source: url, macOS: macOS, appleSilicon: appleSilicon)
                observations.append(.init(target: target, result: result, failure: nil))
            } catch let error as FeedFailure {
                observations.append(.init(target: target, result: nil, failure: error.rawValue))
            }
        }
        return observations
    }
}
