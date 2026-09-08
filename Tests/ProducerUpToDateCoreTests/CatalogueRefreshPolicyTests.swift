// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class CatalogueRefreshPolicyTests: XCTestCase {
    func testFeedConfigurationRejectsCredentialsAndNonPublicURLFeatures() {
        XCTAssertNotNil(CatalogueRefreshPolicy.endpoint("https://updates.example.org/catalogue.json"))
        for value in [nil, "", "http://example.org/feed", "file:///tmp/feed", "https:///",
                      "https://user:password@example.org/feed", "https://example.org:8443/feed",
                      "https://example.org/feed?token=secret", "https://example.org/feed#fragment"] {
            XCTAssertNil(CatalogueRefreshPolicy.endpoint(value), value ?? "nil")
        }
    }

    func testRejectedEndpointPreservesAcceptedCatalogueWithoutNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.Signing.PrivateKey()
        let signed = try SyntheticCatalogueFixture.sign(SyntheticCatalogueFixture.payload(), key: key)
        let store = try CatalogueStore(bundledData: signed,
            publicKey: key.publicKey.rawRepresentation, cacheURL: root.appendingPathComponent("cache"), now: SyntheticCatalogueFixture.now)
        let before = await store.snapshot
        do {
            try await store.refresh(from: URL(string: "http://invalid.example/catalogue")!)
            XCTFail("Insecure transport accepted")
        } catch { XCTAssertEqual(error as? CatalogueError, .network) }
        let after = await store.snapshot
        XCTAssertEqual(before.sequence, after.sequence)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cache").path))
    }

    func testOptInAndDailyAttemptLimitIncludingClockRollback() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertFalse(CatalogueRefreshPolicy.shouldCheck(enabled: false, lastAttempt: nil, now: now))
        XCTAssertTrue(CatalogueRefreshPolicy.shouldCheck(enabled: true, lastAttempt: nil, now: now))
        XCTAssertFalse(CatalogueRefreshPolicy.shouldCheck(enabled: true, lastAttempt: now, now: now))
        XCTAssertFalse(CatalogueRefreshPolicy.shouldCheck(enabled: true, lastAttempt: now.addingTimeInterval(-86_399), now: now))
        XCTAssertTrue(CatalogueRefreshPolicy.shouldCheck(enabled: true, lastAttempt: now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(CatalogueRefreshPolicy.shouldCheck(enabled: true, lastAttempt: now.addingTimeInterval(1), now: now))
    }
}
