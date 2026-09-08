// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

/// Regression coverage for the September 2026 security review: each test pins one hardening
/// decision so it cannot quietly regress.
final class SecurityHardeningTests: XCTestCase {
    private let now = EvidenceFreshness.date("2026-09-07")!
    private let official = URL(string: "https://www.fabfilter.com/download")!

    func testCatalogueRequiresTheSuppliedTrustAnchor() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try SyntheticCatalogueFixture.sign(SyntheticCatalogueFixture.payload(), key: key)
        XCTAssertNoThrow(try CatalogueValidator.verify(signed, publicKey: key.publicKey.rawRepresentation, now: now))
        for invalidKey in [Data(), Data(repeating: 0, count: 31), Curve25519.Signing.PrivateKey().publicKey.rawRepresentation] {
            XCTAssertThrowsError(try CatalogueValidator.verify(signed, publicKey: invalidKey, now: now)) {
                XCTAssertEqual($0 as? CatalogueError, .invalidSignature)
            }
        }
    }

    func testJSONDepthGuardRefusesPathologicalNesting() {
        XCTAssertTrue(JSONDepth.isWithinLimit(Data(String(repeating: "[", count: 31).utf8)))
        XCTAssertFalse(JSONDepth.isWithinLimit(Data(String(repeating: "[", count: 33).utf8)))
        XCTAssertTrue(JSONDepth.isWithinLimit(Data(("{\"a\":\"" + String(repeating: "[", count: 200) + "\"}").utf8)), "Brackets inside strings do not count")
        XCTAssertTrue(JSONDepth.isWithinLimit(Data(("{\"a\":\"\\\"" + String(repeating: "{", count: 200) + "\"}").utf8)), "Escaped quotes stay inside the string")
        let deep = Data((String(repeating: "[", count: 40) + String(repeating: "]", count: 40)).utf8)
        XCTAssertThrowsError(try CatalogueValidator.verify(deep, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation, now: now))
    }

    func testOfficialLinkRequiresPlainHTTPSToAReviewedHost() {
        XCTAssertTrue(CatalogueValidator.isOfficialLink(official))
        for bad in ["http://www.fabfilter.com/", "ftp://www.fabfilter.com/x", "https://www.fabfilter.com:8443/",
                    "https://user@www.fabfilter.com/", "https://www.fabfilter.com.evil.example/", "customscheme://www.fabfilter.com/"] {
            XCTAssertFalse(CatalogueValidator.isOfficialLink(URL(string: bad)!), bad)
        }
    }

    func testFactsCacheRejectsLinksThatAreNotHTTPS() {
        let prefix = "com.d16group."
        let good = PluginReleaseRecord(vendorIdentifierPrefixes: [prefix], productAliases: ["Fixture"], latestVersion: "4.13", sourceURL: DirectVendor.d16.url, checkedOn: "2026-09-07")
        let bad = PluginReleaseRecord(vendorIdentifierPrefixes: [prefix], productAliases: ["Fixture"], latestVersion: "4.13",
                                      sourceURL: URL(string: "ftp://www.fabfilter.com/download")!, checkedOn: "2026-09-07")
        XCTAssertTrue(DirectVendorChecks.validCacheEntries([DirectVendorFacts(vendor: .d16, checkedAt: now, plugins: [good], daws: [])]))
        XCTAssertFalse(DirectVendorChecks.validCacheEntries([DirectVendorFacts(vendor: .d16, checkedAt: now, plugins: [bad], daws: [])]))
    }

    func testOverlayKeepsCatalogueIdentityAndMovesOnlyVersionFields() {
        let prefix = "com.d16group."
        let base = PluginReleaseRecord(vendorIdentifierPrefixes: [prefix], productAliases: ["Fixture 4"], latestVersion: "4.12",
                                       sourceURL: official, checkedOn: "2026-09-01", family: "Fixture", edition: 4)
        let facts = PluginReleaseRecord(vendorIdentifierPrefixes: [prefix], productAliases: ["Fixture 4", "Injected alias"], latestVersion: "4.13",
                                        sourceURL: URL(string: "https://www.fabfilter.com/other")!, checkedOn: "2026-09-07")
        let merged = DirectVendorChecks.overlay([DirectVendorFacts(vendor: .d16, checkedAt: now, plugins: [facts], daws: [])], baseline: [base], now: now)
        XCTAssertEqual(merged.first?.latestVersion, "4.13")
        XCTAssertEqual(merged.first?.checkedOn, "2026-09-07")
        XCTAssertEqual(merged.first?.productAliases, ["Fixture 4"], "Aliases come from the signed catalogue only")
        XCTAssertEqual(merged.first?.sourceURL, official, "The official page comes from the signed catalogue only")
        XCTAssertEqual(merged.first?.family, "Fixture")
        XCTAssertEqual(merged.first?.edition, 4)
    }

    func testHostileVersionStringsAreRejectedQuickly() {
        let hostile = "1." + String(repeating: ".", count: 200_000) + "beta"
        let start = Date()
        XCTAssertNil(VersionComparator.parse(hostile))
        XCTAssertNil(VersionComparator.releaseValue(hostile))
        XCTAssertEqual(VersionComparator.compare(hostile, "1.0"), .incomparable)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1, "A long version string must not stall the parser")
        XCTAssertNotNil(VersionComparator.parse("12.4.5"))
        XCTAssertNotNil(VersionComparator.parse("2.0.0-beta3"))
    }

    func testDisplaySanitiserStripsInvisibleCharactersAndTruncates() {
        XCTAssertEqual(DisplaySanitiser.sanitise("Pro\u{202E}-Q\u{200B} 4\u{0007}"), "Pro-Q 4")
        XCTAssertNil(DisplaySanitiser.sanitise("\u{202E}\u{200B}   "))
        XCTAssertEqual(DisplaySanitiser.sanitise(String(repeating: "a", count: 1_000))?.count, DisplaySanitiser.defaultMaximumLength)
        XCTAssertEqual(DisplaySanitiser.sanitise("v1.2", maximumLength: 3), "v1.")
    }

    func testProvenanceDoesNotOpenANonRegularExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fixture.component")
        let executable = bundle.appendingPathComponent("Contents/MacOS/Fixture")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "com.example.fixture"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(mkfifo(executable.path, 0o600), 0)
        let start = Date()
        XCTAssertEqual(BundleProvenance.read(at: bundle).signature, .notVerified, "A FIFO executable is never handed to Security")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        try FileManager.default.removeItem(at: executable)
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: executable)
        XCTAssertEqual(BundleProvenance.read(at: bundle).signature, .unsigned, "An ordinary unsigned file is still examined")
    }

    func testRunningApplicationsAreRefusedByTheCoreNotOnlyTheView() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fixture", "CFBundleExecutable": "Fixture"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let item = CleanupItem(path: app, kind: .application)
        XCTAssertNil(CleanupSafety(allowedRoots: [root]).validate(item))
        XCTAssertEqual(CleanupSafety(allowedRoots: [root], protectedPaths: [app.resolvingSymlinksInPath().path]).validate(item),
                       "Quit the application before uninstalling it.")
    }

    func testReleaseCheckSkipsTagsThatAreNotVersions() throws {
        let source = AppReleaseCheck.Source("example/studio-upkeep")!
        func release(_ tag: String) -> [String: Any] {
            ["tag_name": tag, "prerelease": false, "draft": false, "html_url": "https://github.com/example/studio-upkeep/releases/tag/\(tag)",
             "assets": ["MK-Studio-Upkeep-0.3.0-macOS.dmg", "SHA256SUMS.txt"].map { name in
                 ["name": name, "state": "uploaded", "size": 1024,
                  "browser_download_url": "https://github.com/example/studio-upkeep/releases/download/\(tag)/\(name)"] as [String: Any]
             }]
        }
        let data = try JSONSerialization.data(withJSONObject: [release("docs-1"), release("v0.3.0")])
        XCTAssertEqual(try AppReleaseCheck.evaluate(data, source: source, installed: "0.2.0", includeBetas: false),
                       .update(version: "v0.3.0", page: URL(string: "https://github.com/example/studio-upkeep/releases/tag/v0.3.0")!))
    }
}
