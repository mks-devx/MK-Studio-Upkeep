// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class DirectVendorChecksTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z")!
    private func record(_ name: String = "Syntorus 2", _ version: String = "2.0.0", vendor: DirectVendor = .d16) -> PluginReleaseRecord {
        .init(vendorIdentifierPrefixes: [vendor.prefix], productAliases: [name], latestVersion: version, sourceURL: vendor.url, checkedOn: "2026-09-01")
    }
    private func d16(_ version: String = "2.1.0") -> String {
        "<h5 class=\"card-header\">Syntorus 2 \(version)</h5><a href=\"https://cdn.d16.pl/installers/Syntorus2/Syntorus2-\(version).dmg\">Mac OS</a>"
    }
    private func observation(_ page: String, vendor: DirectVendor = .d16, date: Date? = nil) -> DirectVendorObservation {
        .init(vendor: vendor, checkedAt: date ?? now, page: page)
    }
    func testExactMacReleaseAndDate() throws {
        let found = try DirectVendorChecks.records(from: observation(d16()), baseline: [record()], now: now)
        XCTAssertEqual(found.first?.latestVersion, "2.1.0")
        XCTAssertEqual(found.first?.checkedOn, "2026-09-05")
        XCTAssertEqual(found.first?.sourceURL, DirectVendor.d16.url)
        XCTAssertEqual(found.first?.downloadURL?.host, "cdn.d16.pl")
    }
    func testRejectsSpoofWrongPlatformDuplicateAndMismatchedInstaller() {
        for page in [d16().replacingOccurrences(of: "cdn.d16.pl", with: "cdn.d16.pl.evil.example"),
                     d16().replacingOccurrences(of: "Mac OS", with: "Windows"), d16() + d16(),
                     d16().replacingOccurrences(of: "2.1.0.dmg", with: "2.0.0.dmg"), "<h5>Unknown layout</h5>"] {
            XCTAssertThrowsError(try DirectVendorChecks.records(from: observation(page), baseline: [record()], now: now))
        }
    }
    func testMissingProductRejectsEntireSourceAndDoesNotRefreshDate() {
        let baseline = [record(), record("Other")]
        let result = DirectVendorChecks.overlay([observation(d16())], baseline: baseline, now: now)
        XCTAssertEqual(result, baseline)
    }
    func testRegressionAndIncomparableVersionsRejected() {
        XCTAssertThrowsError(try DirectVendorChecks.records(from: observation(d16("1.0.0")), baseline: [record()], now: now))
        XCTAssertThrowsError(try DirectVendorChecks.records(from: observation(d16("2.1.0-beta")), baseline: [record()], now: now))
    }
    func testFutureStaleAndOversizedPagesRejected() {
        for observation in [observation(d16(), date: now.addingTimeInterval(1)),
                            observation(d16(), date: now.addingTimeInterval(-31 * 86_400)),
                            observation(String(repeating: "x", count: DirectVendorChecks.maximumBytes + 1))] {
            XCTAssertThrowsError(try DirectVendorChecks.records(from: observation, baseline: [record()], now: now))
        }
    }
    func testKiloheartsRequiresSharedStatementAndAgreement() throws {
        let page = "all have the same version number <a href=\"/data/install/_/mac\">Kilohearts Installer 2.4.0 for Mac</a><h3><a href=\"/changelog#2.4.0\">Changes</a></h3>"
        let baseline = [record("Phase Plant", "2.3.0", vendor: .kilohearts)]
        XCTAssertEqual(try DirectVendorChecks.records(from: observation(page, vendor: .kilohearts), baseline: baseline, now: now).first?.latestVersion, "2.4.0")
        for invalid in [page.replacingOccurrences(of: "all have the same version number", with: ""),
                        page.replacingOccurrences(of: "changelog#2.4.0", with: "changelog#2.5.0")] {
            XCTAssertThrowsError(try DirectVendorChecks.records(from: observation(invalid, vendor: .kilohearts), baseline: baseline, now: now))
        }
    }
    func testOverlayLeavesUnrelatedEvidenceAndRejectsRegressionAgainstNewBaseline() {
        let unrelated = record("Other", vendor: .kilohearts)
        let result = DirectVendorChecks.overlay([observation(d16())], baseline: [record(), unrelated], now: now)
        XCTAssertEqual(result[1], unrelated)
        let newer = record("Syntorus 2", "3.0.0")
        XCTAssertEqual(DirectVendorChecks.overlay([observation(d16())], baseline: [newer], now: now), [newer])
    }
    func testCancellationBeforeRequest() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await DirectVendorChecks.fetch(.d16)
                XCTFail("A cancelled check must not make a request")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
    }
    private func facts(_ page: String = "", vendor: DirectVendor = .d16, date: Date? = nil, baseline: [PluginReleaseRecord]? = nil) throws -> DirectVendorFacts {
        try DirectVendorChecks.facts(from: observation(page.isEmpty ? d16() : page, vendor: vendor, date: date), baseline: baseline ?? [record()], dawBaseline: nil, now: now)
    }
    func testOnlyReviewedSourcesAreActiveAndInactiveSourcesAreNeverRequested() async {
        XCTAssertTrue(DirectVendor.active.isEmpty, "No live plugin or DAW source may be requested")
        for vendor in DirectVendor.allCases where !vendor.isActive {
            XCTAssertNotNil(vendor.inactiveReason, vendor.rawValue)
            do {
                _ = try await DirectVendorChecks.fetch(vendor)
                XCTFail("\(vendor) must not be requested")
            } catch { XCTAssertEqual(error as? DirectVendorError, .notEnabled, vendor.rawValue) }
        }
        for vendor in DirectVendor.active { XCTAssertNil(vendor.inactiveReason) }
    }

    func testRequestsIdentifyTheAppAndSpaceSameHostRequests() {
        XCTAssertTrue(DirectVendorChecks.userAgent.hasPrefix("MKStudioUpkeep/"))
        XCTAssertTrue(DirectVendorChecks.userAgent.contains("+https://github.com/mks-devx/MK-Studio-Upkeep"))
        XCTAssertFalse(DirectVendorChecks.userAgent.contains("\n"))
        XCTAssertEqual(DirectVendorChecks.politenessDelay(before: .d16, after: nil), 0)
        XCTAssertEqual(DirectVendorChecks.politenessDelay(before: .tdrKotelnikov, after: .d16), 0)
        XCTAssertEqual(DirectVendorChecks.politenessDelay(before: .tdrKotelnikov, after: .tdrNova), 1)
        XCTAssertEqual(DirectVendorChecks.politenessDelay(before: .kilohearts, after: .kilohearts), 1.5)
    }
    func testFactsKeepVersionsNotPagesAndDoNotRenewDate() throws {
        let extracted = try facts()
        XCTAssertEqual(extracted.plugins.map(\.latestVersion), ["2.1.0"])
        XCTAssertTrue(extracted.daws.isEmpty)
        let encoded = try String(decoding: JSONEncoder().encode([extracted]), as: UTF8.self)
        XCTAssertFalse(encoded.contains("card-header"), "No page markup may survive into the cache")
        XCTAssertEqual(DirectVendorChecks.overlay([extracted], baseline: [record()], now: now).first?.latestVersion, "2.1.0")
        XCTAssertEqual(DirectVendorChecks.overlay([extracted], baseline: [record()], now: now.addingTimeInterval(31 * 86_400)), [record()])
        let newer = record("Syntorus 2", "3.0.0")
        XCTAssertEqual(DirectVendorChecks.overlay([extracted], baseline: [newer], now: now), [newer], "A fresher signed catalogue wins")
        let unrelated = record("Other", vendor: .kilohearts)
        XCTAssertEqual(DirectVendorChecks.overlay([extracted], baseline: [unrelated], now: now), [unrelated])
        let stale = DirectVendorFacts(vendor: .d16, checkedAt: now, parserVersion: DirectVendorFacts.currentParserVersion - 1, plugins: extracted.plugins, daw: nil)
        XCTAssertEqual(DirectVendorChecks.overlay([stale], baseline: [record()], now: now), [record()])
    }
    func testFactsCacheRoundTripDropsInactiveAndInvalidEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("facts.json")
        XCTAssertTrue(DirectVendorChecks.loadCache(url).isEmpty)
        XCTAssertTrue(DirectVendorChecks.loadCache(folder).isEmpty)
        let pageFacts = try facts()
        try DirectVendorChecks.saveCache([pageFacts], to: url)
        XCTAssertTrue(DirectVendorChecks.loadCache(url).isEmpty)
        let encoded = try JSONEncoder().encode([pageFacts])
        let legacy = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "\"d16\"", with: "\"retired-index\"")
        try Data(legacy.utf8).write(to: url)
        XCTAssertTrue(DirectVendorChecks.loadCache(url).isEmpty, "Removed source caches must be ignored")
        XCTAssertNil(DirectVendor(rawValue: "retired-index"))
    }

    func testDAWFactsRequireMatchingIdentityAndRejectRegression() throws {
        let page = "<h1>Logic Pro for Mac release notes</h1><h2>New in Logic Pro 12.3.1</h2><p>These release notes apply to both the one-time purchase and Apple Creator Studio versions of Logic Pro for Mac.</p>"
        let extracted = try DirectVendorChecks.facts(from: observation(page, vendor: .logic), baseline: [], dawBaseline: nil, now: now)
        XCTAssertEqual(extracted.daws.first?.latestVersion, "12.3.1")
        XCTAssertTrue(extracted.plugins.isEmpty)
        XCTAssertEqual(DirectVendorChecks.dawRelease(from: extracted, baseline: nil, now: now)?.latestVersion, "12.3.1")
        let newer = DAWReleaseRecord(definitionID: "logic-pro", latestVersion: "12.4", sourceURL: DirectVendor.logic.url, checkedOn: "2026-09-05")
        XCTAssertNil(DirectVendorChecks.dawRelease(from: extracted, baseline: newer, now: now))
        XCTAssertNil(DirectVendorChecks.dawRelease(from: extracted, baseline: nil, now: now.addingTimeInterval(31 * 86_400)))
        let mismatched = DirectVendorFacts(vendor: .garageband, checkedAt: now, plugins: [], daws: extracted.daws)
        XCTAssertNil(DirectVendorChecks.dawRelease(from: mismatched, baseline: nil, now: now))
        XCTAssertFalse(DirectVendorChecks.validCacheEntries([mismatched]))
        XCTAssertTrue(DirectVendorChecks.validCacheEntries([extracted]))
    }
}
