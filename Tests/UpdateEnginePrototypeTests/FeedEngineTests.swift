// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import UpdateEnginePrototypeSupport

final class FeedEngineTests: XCTestCase {
    let url = URL(string: "https://updates.example.com/feed.xml")!
    func xml(_ items: String) -> Data {
        Data("<rss xmlns:s='\(SparkleFeed.namespace)'><channel>\(items)</channel></rss>".utf8)
    }
    func item(_ build: String, version: String? = nil, extra: String = "") -> String {
        "<item><s:version>\(build)</s:version><s:shortVersionString>\(version ?? build)</s:shortVersionString>\(extra)</item>"
    }
    func evaluate(_ data: Data, installed: String = "100", os: String = "13.0", silicon: Bool = true) throws -> FeedComparison {
        try FeedComparison.evaluate(SparkleFeed.parse(data), installedBuild: installed, source: url, macOS: os, appleSilicon: silicon)
    }
    func testUsesBuildNumbersInsteadOfComparingMarketingVersionToBuild() throws {
        let result = try evaluate(xml(item("101", version: "1.2.0")))
        XCTAssertEqual(result.update?.build, "101")
        XCTAssertEqual(result.update?.version, "1.2.0")
        XCTAssertFalse(result.noUpdateFound)
    }
    func testOldAndNewInstalledCopiesGetDifferentResults() throws {
        let feed = xml(item("101", version: "1.2.0"))
        XCTAssertNotNil(try evaluate(feed, installed: "100").update)
        XCTAssertTrue(try evaluate(feed, installed: "101").noUpdateFound)
        XCTAssertTrue(try evaluate(feed, installed: "102").noUpdateFound)
    }
    func testMajorUpgradeAndSameEditionUpdateAreSeparate() throws {
        let result = try evaluate(xml(item("105", version: "1.5") + item("210", version: "2.1", extra: "<s:minimumAutoupdateVersion>200</s:minimumAutoupdateVersion>")))
        XCTAssertEqual(result.update?.version, "1.5")
        XCTAssertEqual(result.newerEdition?.version, "2.1")
    }
    func testMajorNumberAloneDoesNotInferAnEditionOrPrice() throws {
        let result = try evaluate(xml(item("200", version: "2.0")))
        XCTAssertNotNil(result.update)
        XCTAssertNil(result.newerEdition)
    }
    func testOSHardwareAndMinimumBuildConditionsAreRespected() throws {
        XCTAssertThrowsError(try evaluate(xml(item("200", extra: "<s:minimumSystemVersion>14.0</s:minimumSystemVersion>"))))
        XCTAssertThrowsError(try evaluate(xml(item("200", extra: "<s:maximumSystemVersion>12.0</s:maximumSystemVersion>"))))
        XCTAssertThrowsError(try evaluate(xml(item("200", extra: "<s:minimumUpdateVersion>150</s:minimumUpdateVersion>"))))
        XCTAssertThrowsError(try evaluate(xml(item("200", extra: "<s:hardwareRequirements>arm64</s:hardwareRequirements>")), silicon: false))
        XCTAssertThrowsError(try evaluate(xml(item("200", extra: "<s:minimumSystemVersion>unknown</s:minimumSystemVersion>"))))
    }
    func testBetaAndNonMacReleasesNeverReplaceStableRelease() throws {
        let value = xml(item("101") + item("200", version: "2.0beta1") + item("300", extra: "<s:channel>beta</s:channel>") + "<item><enclosure s:version='400' s:os='windows'/></item>")
        XCTAssertEqual(try evaluate(value).update?.build, "101")
    }
    func testLegacyEnclosureAttributesRespectNamespace() throws {
        XCTAssertEqual(try evaluate(xml("<item><enclosure s:version='101' s:shortVersionString='1.1'/></item>")).update?.version, "1.1")
        XCTAssertThrowsError(try evaluate(Data("<rss xmlns:s='https://wrong.example.com'><channel>\(item("101"))</channel></rss>".utf8)))
    }
    func testMalformedOversizedAndEntityDocumentsAreRejected() {
        XCTAssertThrowsError(try SparkleFeed.parse(Data(repeating: 32, count: SparkleFeed.maximumBytes + 1)))
        XCTAssertThrowsError(try SparkleFeed.parse(Data("<!DOCTYPE rss [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><rss>&a;</rss>".utf8)))
        XCTAssertThrowsError(try SparkleFeed.parse(Data("<rss><channel><item>".utf8)))
        let utf16DTD = "<?xml version='1.0' encoding='UTF-16BE'?><!DOCTYPE rss [<!ENTITY a 'expanded'>]><rss>&a;</rss>".data(using: .utf16BigEndian)!
        XCTAssertThrowsError(try SparkleFeed.parse(utf16DTD))
        XCTAssertThrowsError(try SparkleFeed.parse(xml(String(repeating: "<x>", count: 18) + String(repeating: "</x>", count: 18))))
        XCTAssertThrowsError(try SparkleFeed.parse(xml(String(repeating: item("101"), count: 201))))
    }
    func testAmbiguousOrUnsupportedFeedNeverProducesCurrent() {
        XCTAssertThrowsError(try evaluate(xml(item("101", extra: "<s:version>102</s:version>"))))
        XCTAssertThrowsError(try evaluate(xml(item("101") + item("101", version: "different"))))
        XCTAssertThrowsError(try evaluate(xml(item("101", extra: "<s:informationalUpdate/>"))))
        XCTAssertThrowsError(try evaluate(xml(item("101") + item("101.0", version: "2.0"))))
        XCTAssertThrowsError(try evaluate(xml("<item><s:version>10<x/>1</s:version></item>")))
        XCTAssertThrowsError(try evaluate(xml(item("101")), installed: "release-special"))
        XCTAssertThrowsError(try evaluate(xml(item("101")), installed: "100beta1"))
    }
    func testResultsExpireAndFutureTimestampsAreNotFresh() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = try FeedComparison.evaluate(SparkleFeed.parse(xml(item("101"))), installedBuild: "100", source: url, macOS: "13.0", appleSilicon: true, now: now)
        XCTAssertTrue(result.isFresh(at: now))
        XCTAssertFalse(result.isFresh(at: now.addingTimeInterval(86_401)))
        XCTAssertFalse(result.isFresh(at: now.addingTimeInterval(-1)))
    }
    func testSharedFeedAcrossProductsIsNotAssumedToMatchBoth() {
        let plan = FeedCoveragePlan(targets: [target("one", "100"), target("two", "100")])
        XCTAssertEqual(plan.productCount, 2)
        XCTAssertEqual(plan.eligible.count, 0)
    }
    private func target(_ product: String, _ build: String) -> FeedTarget {
        .init(productID: product, name: "Example Product", copy: "Example copy", build: build, source: url)
    }
    func testPermissionGateMakesZeroFetchCalls() {
        let counter = Counter()
        let plan = FeedCoveragePlan(targets: [target("one", "100")])
        XCTAssertThrowsError(try FeedCheckRunner.check(plan, allowNetwork: false, macOS: "13.0", appleSilicon: true, fetch: { _ in counter.increment(); return Data() }))
        XCTAssertEqual(counter.value, 0)
    }
    func testOneFetchStillComparesEachCopySeparately() throws {
        let counter = Counter(), data = xml(item("101"))
        let plan = FeedCoveragePlan(targets: [target("one", "100"), target("one", "101")])
        let results = try FeedCheckRunner.check(plan, allowNetwork: true, macOS: "13.0", appleSilicon: true, fetch: { _ in counter.increment(); return data })
        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(results[0].result?.update)
        XCTAssertTrue(results[1].result?.noUpdateFound == true)
    }
    func testFailedSourceNeverBecomesNoUpdateFound() throws {
        let plan = FeedCoveragePlan(targets: [target("one", "100")])
        let results = try FeedCheckRunner.check(plan, allowNetwork: true, macOS: "13.0", appleSilicon: true, fetch: { _ in throw FeedFailure.network })
        XCTAssertNil(results[0].result)
        XCTAssertNotNil(results[0].failure)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
