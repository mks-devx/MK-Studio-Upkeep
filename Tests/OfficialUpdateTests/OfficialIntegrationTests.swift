// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
import ProducerUpToDateCore
@testable import OfficialUpdateSupport

final class OfficialIntegrationTests: XCTestCase {
    static let current = #"<h2>Download FabFilter Pro-Q 4</h2><p>EQ<br>4.02 &mdash; Jan 1, 2025</p><a href="https://cdn-b.fabfilter.com/downloads/ffproq402.dmg">Download for macOS</a>"#
    func fixture(_ root: URL, folder: String, name: String, identifier: String, version: String) throws -> URL {
        let bundle = root.appendingPathComponent(folder)
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": name, "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version, "CFBundleVersion": "999"], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
    static func scan(_ root: URL) async throws -> StudioScanResult {
        try await ScanPipeline.run(configuration: .init(locations: [.init(url: root, format: .audioUnit)]), scanDAWs: false)
    }
    func testScannerThroughRunnerKeepsCopiesAndFetchesOnePage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, folder: "old.component", name: "FabFilter Pro-Q 4", identifier: "com.fabfilter.Pro-Q.AU.4", version: "4.01")
        _ = try fixture(root, folder: "new.component", name: "FabFilter Pro-Q 4", identifier: "com.fabfilter.Pro-Q.AU.4", version: "4.02")
        let result = try await Self.scan(root)
        let targets = OfficialTarget.discover(products: result.products, daws: [], directory: try .bundled())
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.filter { $0.entry != nil }.count, 2)
        final class Counter: @unchecked Sendable {
            let lock = NSLock(); var count = 0
            func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
        }
        let counter = Counter()
        let observations = try OfficialCheckRunner.check(targets, allowNetwork: true) { url in
            XCTAssertEqual(url.absoluteString, "https://www.fabfilter.com/download")
            counter.increment(); return Data(Self.current.utf8)
        }
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(Set(observations.map { $0.state(at: Date()).rawValue }), Set(["Update available", "Matches official release"]))
        XCTAssertEqual(Set(observations.compactMap(\.installed)), ["4.01", "4.02"])
        XCTAssertFalse(observations.contains { $0.installed == "999" })
        let failed = try OfficialCheckRunner.check(targets, allowNetwork: true) { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(failed.allSatisfy { $0.state(at: Date()) == .failed && $0.latest == nil })
        try FileManager.default.removeItem(at: root.appendingPathComponent("old.component/Contents/Info.plist"))
        let changed = try OfficialCheckRunner.check([targets.first { $0.installed == "4.01" }!], allowNetwork: true) { _ in
            XCTFail("Changed metadata must prevent the request"); return Data()
        }
        XCTAssertEqual(changed.first?.state(at: Date()), .failed)
    }
    func testLegacyEditionAndDAWRequireMacRelease() throws {
        let directory = try OfficialSourceDirectory.bundled()
        let legacy = directory.entries.first { $0.id == "fabfilter-pro-q-3" }!
        let page = #"<h3>Pro-Q 3.02</h3><a href="https://cdn-b.fabfilter.com/downloads/ffproq302.dmg">macOS</a><h3>Pro-Q 2.99</h3>"#
        XCTAssertEqual(try OfficialReleaseParser.version(Data(page.utf8), entry: legacy), "3.02")
        XCTAssertThrowsError(try OfficialReleaseParser.version(Data(Self.current.utf8), entry: legacy))
        let reaper = directory.entries.first { $0.id == "reaper-7" }!
        let dawPage = #"<title>REAPER | Download</title><div class='hdrbottom'>Version 7.02: January 1, 2025</div><a href="files/7.x/reaper702_universal.dmg" title="Download REAPER for macOS Universal">macOS</a>"#
        XCTAssertEqual(try OfficialReleaseParser.version(Data(dawPage.utf8), entry: reaper), "7.02")
        for invalid in [dawPage + dawPage, dawPage.replacingOccurrences(of: "7.02", with: "8.02"), dawPage.replacingOccurrences(of: "702_universal", with: "701_universal"), dawPage.replacingOccurrences(of: "macOS Universal", with: "Windows")] {
            XCTAssertThrowsError(try OfficialReleaseParser.version(Data(invalid.utf8), entry: reaper))
        }
    }
    func testDirectoryRejectsUntrustedDestinationAndDeepJSON() throws {
        let encoded = try JSONEncoder().encode(OfficialSourceDirectory.bundled())
        let string = String(data: encoded, encoding: .utf8)!
        XCTAssertThrowsError(try OfficialSourceDirectory.decode(Data(string.replacingOccurrences(of: "www.fabfilter.com", with: "untrusted.example").utf8)))
        XCTAssertThrowsError(try OfficialSourceDirectory.decode(Data((String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40)).utf8)))
    }
    @MainActor func testSessionOptInWithdrawalAndRescanDiscardLateResults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, folder: "copy.component", name: "FabFilter Pro-Q 4", identifier: "com.fabfilter.Pro-Q.AU.4", version: "4.01")
        let result = try await Self.scan(root)
        let session = OfficialUpdateSession()
        session.reset(products: result.products)
        XCTAssertFalse(session.optedIn)
        session.check { _ in XCTFail("Consent missing"); return Data() }
        XCTAssertFalse(session.isChecking)
        session.optedIn = true
        session.check { _ in
            Thread.sleep(forTimeInterval: 0.15)
            return Data(Self.current.utf8)
        }
        XCTAssertTrue(session.isChecking)
        try await Task.sleep(for: .milliseconds(30))
        session.optedIn = false
        session.reset()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(session.isChecking)
        XCTAssertTrue(session.observations.isEmpty)
        XCTAssertTrue(session.targets.isEmpty)
    }
    func testDAWScannerAndRunnerCompareMarketingVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try fixture(root, folder: "REAPER.app", name: "REAPER", identifier: "com.cockos.reaper", version: "7.01")
        let scan = try DAWScanner().scanReport(configuration: .init(applicationRoots: [root], definitions: DAWDefinition.known))
        let targets = OfficialTarget.discover(products: [], daws: scan.records, directory: try .bundled())
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.entry?.id, "reaper-7")
        let page = #"<title>REAPER | Download</title><div class='hdrbottom'>Version 7.02: January 1, 2025</div><a href="files/7.x/reaper702_universal.dmg" title="Download REAPER for macOS Universal">macOS</a>"#
        let observations = try OfficialCheckRunner.check(targets, allowNetwork: true) { _ in Data(page.utf8) }
        XCTAssertEqual(observations.first?.state(at: Date()), .update)
    }
    func testFilesChangedDuringFetchDoNotProduceUpdate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try fixture(root, folder: "copy.component", name: "FabFilter Pro-Q 4", identifier: "com.fabfilter.Pro-Q.AU.4", version: "4.01")
        let scan = try await Self.scan(root)
        let targets = OfficialTarget.discover(products: scan.products, daws: [], directory: try .bundled())
        let observations = try OfficialCheckRunner.check(targets, allowNetwork: true) { _ in
            try FileManager.default.removeItem(at: bundle.appendingPathComponent("Contents/Info.plist"))
            return Data(Self.current.utf8)
        }
        XCTAssertEqual(observations.first?.state(at: Date()), .failed)
    }
    func testMalformedLargeAndNonUTF8ResponsesFailClosed() throws {
        let entry = try OfficialSourceDirectory.bundled().entries[0]
        for data in [Data([0xff,0xfe,0x00]), Data(repeating: 32, count: 1_048_577), Data("<html>Sign in to continue</html>".utf8)] {
            XCTAssertThrowsError(try OfficialReleaseParser.version(data, entry: entry))
        }
    }
}
