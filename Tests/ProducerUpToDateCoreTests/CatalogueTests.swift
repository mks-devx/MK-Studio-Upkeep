// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class CatalogueTests: XCTestCase {
    private let now = EvidenceFreshness.date("2026-09-08")!

    func testSyntheticSignedSnapshotPreservesEvidence() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = try payload()
        let signed = try sign(data, key)
        let snapshot = try CatalogueValidator.verify(signed, publicKey: key.publicKey.rawRepresentation, now: now)
        XCTAssertEqual(snapshot.plugins.map(\.productAliases), SyntheticCatalogueFixture.snapshot.plugins.map(\.productAliases))
        XCTAssertEqual(snapshot.daws.map(\.definitionID), ["fixture-daw"])
        XCTAssertEqual(snapshot.drivers.map(\.bundleIdentifier), ["com.example.driver"])
        XCTAssertEqual(snapshot.architectures, SyntheticCatalogueFixture.snapshot.architectures)
        XCTAssertEqual(snapshot.releaseNotes, SyntheticCatalogueFixture.snapshot.releaseNotes)
        XCTAssertEqual(try JSONDecoder().decode(SignedCatalogueEnvelope.self, from: signed).payload, data)
    }

    func testRejectsTamperedUnsignedWrongKeyFutureAndMalformedSnapshots() throws {
        let key = Curve25519.Signing.PrivateKey()
        let valid = try payload()
        let signed = try sign(valid, key)
        XCTAssertNoThrow(try CatalogueValidator.verify(signed, publicKey: key.publicKey.rawRepresentation, now: now))
        XCTAssertThrowsError(try CatalogueValidator.verify(valid, publicKey: key.publicKey.rawRepresentation, now: now))
        XCTAssertThrowsError(try CatalogueValidator.verify(signed, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation, now: now))
        let envelope = try JSONDecoder().decode(SignedCatalogueEnvelope.self, from: signed)
        let tampered = try JSONEncoder().encode(SignedCatalogueEnvelope(payload: valid + Data([32]), signature: envelope.signature))
        XCTAssertThrowsError(try CatalogueValidator.verify(tampered, publicKey: key.publicKey.rawRepresentation, now: now))
        for mutation: (inout [String: Any]) -> Void in [
            { $0["schemaVersion"] = 99 },
            { $0["generatedOn"] = "2099-01-01" },
            { $0["plugins"] = [["latestVersion": "1.0"]] }
        ] {
            let invalid = try payload(mutation)
            XCTAssertThrowsError(try CatalogueValidator.verify(sign(invalid, key), publicKey: key.publicKey.rawRepresentation, now: now))
        }
    }

    func testEditionFamiliesValidateStrictly() throws {
        let key = Curve25519.Signing.PrivateKey()
        func index(_ alias: String, in snapshot: [String: Any]) -> Int {
            (snapshot["plugins"] as! [[String: Any]]).firstIndex { ($0["productAliases"] as! [String]).first == alias }!
        }
        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("family without edition", { s in var r = s["plugins"] as! [[String: Any]]; r[index("Fixture EQ 4", in: s)].removeValue(forKey: "edition"); s["plugins"] = r }),
            ("edition without family", { s in var r = s["plugins"] as! [[String: Any]]; r[index("Fixture EQ 4", in: s)].removeValue(forKey: "family"); s["plugins"] = r }),
            ("edition differs from release major", { s in var r = s["plugins"] as! [[String: Any]]; r[index("Fixture EQ 4", in: s)]["edition"] = 3; s["plugins"] = r }),
            ("zero edition", { s in var r = s["plugins"] as! [[String: Any]]; r[index("Fixture EQ 4", in: s)]["edition"] = 0; r[index("Fixture EQ 4", in: s)]["latestVersion"] = "0.9"; s["plugins"] = r }),
            ("duplicate edition in family", { s in var r = s["plugins"] as! [[String: Any]]; let i = index("Fixture Dynamics 3", in: s); r[i]["family"] = "fixture:eq"; r[i]["edition"] = 3; s["plugins"] = r }),
            ("family across vendor lines", { s in var r = s["plugins"] as! [[String: Any]]; let i = index("Other Fixture", in: s); r[i]["family"] = "fixture:eq"; r[i]["edition"] = 2; s["plugins"] = r }),
            ("empty family name", { s in var r = s["plugins"] as! [[String: Any]]; r[index("Fixture EQ 4", in: s)]["family"] = "  "; s["plugins"] = r })
        ]
        for (label, mutation) in mutations {
            let invalid = try payload(mutation)
            XCTAssertThrowsError(try CatalogueValidator.verify(sign(invalid, key), publicKey: key.publicKey.rawRepresentation, now: now), label)
        }
        let unlinked = try payload { s in
            var r = s["plugins"] as! [[String: Any]]
            for i in r.indices { r[i].removeValue(forKey: "family"); r[i].removeValue(forKey: "edition") }
            s["plugins"] = r
        }
        XCTAssertNoThrow(try CatalogueValidator.verify(sign(unlinked, key), publicKey: key.publicKey.rawRepresentation, now: now), "Families are optional")
        let snapshot = try CatalogueValidator.verify(sign(payload(), key), publicKey: key.publicKey.rawRepresentation, now: now)
        XCTAssertEqual(Set(snapshot.plugins.compactMap(\.family)), ["fixture:eq", "fixture:dynamics"])
    }

    func testNewOfficialHostsDoNotAllowLookalikesInSignedData() throws {
        let key = Curve25519.Signing.PrivateKey()
        for url in ["https://kilohearts.com.example.org/download", "http://d16.pl/installers",
                    "https://tal-software.com@evil.example/releases", "https://valhalladsp.com:8443/releases"] {
            let invalid = try payload { snapshot in
                var records = snapshot["plugins"] as! [[String: Any]]
                records[0]["sourceURL"] = url
                snapshot["plugins"] = records
            }
            XCTAssertThrowsError(try CatalogueValidator.verify(sign(invalid, key), publicKey: key.publicKey.rawRepresentation, now: now), url)
        }
    }

    func testDAWMajorScopeAndNewOfficialSources() throws {
        let key = Curve25519.Signing.PrivateKey()
        for major in [-1, 0, 11, 13] {
            let invalid = try payload { snapshot in
                var records = snapshot["daws"] as! [[String: Any]]
                records[0]["latestVersion"] = "12.4.5"
                records[0]["majorVersion"] = major
                snapshot["daws"] = records
            }
            XCTAssertThrowsError(try CatalogueValidator.verify(sign(invalid, key), publicKey: key.publicKey.rawRepresentation, now: now))
        }
        for host in ["support.apple.com", "www.reaper.fm", "www.reasonstudios.com"] {
            let valid = try payload { snapshot in
                var records = snapshot["daws"] as! [[String: Any]]
                records[0]["latestVersion"] = "12.4.5"
                records[0]["majorVersion"] = 12
                records[0]["sourceURL"] = "https://\(host)/fixture"
                snapshot["daws"] = records
            }
            XCTAssertNoThrow(try CatalogueValidator.verify(sign(valid, key), publicKey: key.publicKey.rawRepresentation, now: now))
            let spoof = try payload { snapshot in
                var records = snapshot["daws"] as! [[String: Any]]
                records[0]["sourceURL"] = "https://\(host).evil.example/fixture"
                snapshot["daws"] = records
            }
            XCTAssertThrowsError(try CatalogueValidator.verify(sign(spoof, key), publicKey: key.publicKey.rawRepresentation, now: now))
        }
    }

    func testCacheRetainsValidSnapshotAcrossFailureAndRejectsRollback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let first = try sign(payload(), key)
        let cache = root.appendingPathComponent("catalogue.json")
        let store = try CatalogueStore(bundledData: first, publicKey: key.publicKey.rawRepresentation, cacheURL: cache, now: now)
        let second = try sign(payload { $0["sequence"] = 2 }, key)
        try await store.accept(second, now: now)
        do { try await store.accept(first, now: now); XCTFail("Rollback accepted") } catch {}
        do { try await store.accept(Data(), now: now); XCTFail("Unsigned data accepted") } catch {}
        let snapshot = await store.snapshot
        XCTAssertEqual(snapshot.sequence, 2)
        XCTAssertEqual(try Data(contentsOf: cache), second)
        let reopened = try CatalogueStore(bundledData: first, publicKey: key.publicKey.rawRepresentation, cacheURL: cache, now: now)
        let reloaded = await reopened.snapshot
        XCTAssertEqual(reloaded.sequence, 2)
        try Data("broken".utf8).write(to: cache)
        let fallback = try CatalogueStore(bundledData: first, publicKey: key.publicKey.rawRepresentation, cacheURL: cache, now: now)
        let fallbackSnapshot = await fallback.snapshot
        let failure = await fallback.lastFailure
        XCTAssertEqual(fallbackSnapshot.sequence, 1)
        XCTAssertNotNil(failure)
    }

    func testSameSequenceConflictingPayloadRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let store = try CatalogueStore(bundledData: sign(payload(), key), publicKey: key.publicKey.rawRepresentation, cacheURL: root.appendingPathComponent("cache"), now: now)
        do {
            try await store.accept(sign(payload { $0["releaseNotes"] = [] }, key), now: now)
            XCTFail("Conflicting sequence accepted")
        } catch { XCTAssertEqual(error as? CatalogueError, .rollback) }
    }

    func testFreshnessAndPrereleaseBoundaries() {
        XCTAssertFalse(EvidenceFreshness.isFresh("2026-07-28", now: now))
        XCTAssertFalse(EvidenceFreshness.isFresh("2026-02-30", now: now))
        XCTAssertFalse(EvidenceFreshness.isFresh("2026-09-09", now: now))
        XCTAssertTrue(EvidenceFreshness.isFresh("2026-09-05", now: now))
        XCTAssertEqual(VersionComparator.releaseValue("1.2beta3"), "1.2beta3")
        XCTAssertNil(VersionComparator.releaseValue("1.2 mystery"))
        XCTAssertEqual(VersionComparator.compare("1.2beta3", "1.2"), .older)
    }

    func testReleaseNotesRangeSkipsWrongProductMissingStaleAndDuplicateEvidence() {
        let url = URL(string: "https://www.ableton.com/en/release-notes/live-12/")!
        func note(_ v: String, product: String = "fixture", date: String = "2026-09-05") -> ReviewedReleaseNotes {
            ReviewedReleaseNotes(productID: product, version: v, checkedOn: date, sourceURL: url)
        }
        let notes = [note("1.0"), note("1.1"), note("1.2"), note("1.3"), note("1.4"), note("1.25", product: "other"), note("1.15", date: "2026-01-01")]
        let result = ReleaseNotesQuery.releases(productID: "fixture", installed: "1.0", available: "1.3", notes: notes, now: now)
        XCTAssertEqual(result.map(\.version), ["1.3", "1.2", "1.1"])
        XCTAssertTrue(result.allSatisfy { $0.highlights.isEmpty })
        XCTAssertTrue(ReleaseNotesQuery.releases(productID: "fixture", installed: "unknown", available: "1.3", notes: notes, now: now).isEmpty)
        XCTAssertTrue(ReleaseNotesQuery.releases(productID: "fixture", installed: "1", available: "1.1", notes: [note("1.1"), note("1.1")], now: now).isEmpty)
    }

    private func payload(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        try SyntheticCatalogueFixture.payload(mutate)
    }
    private func sign(_ data: Data, _ key: Curve25519.Signing.PrivateKey) throws -> Data {
        try JSONEncoder().encode(SignedCatalogueEnvelope(payload: data, signature: key.signature(for: data)))
    }
}
