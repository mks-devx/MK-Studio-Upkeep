// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class PluginDownloadPolicyTests: XCTestCase {
    private let good = "https://cdn.d16.pl/installers/Drumazon2/Drumazon2-2.0.7.dmg"
    private func release(download: String? = nil) -> PluginReleaseRecord {
        .init(vendorIdentifierPrefixes: ["com.d16group."], productAliases: ["Drumazon 2"], latestVersion: "2.0.7",
              sourceURL: URL(string: "https://d16.pl/installers")!, checkedOn: "2026-09-05", downloadURL: download.flatMap(URL.init(string:)))
    }
    func testVersionBoundMacDownloadOnly() {
        XCTAssertTrue(PluginDownloadPolicy.isAllowed(URL(string: good)!, for: release()))
        for bad in [good + "?token=secret", good + "#fragment", good.replacingOccurrences(of: "https:", with: "http:"),
                    good.replacingOccurrences(of: "cdn.d16.pl", with: "cdn.d16.pl.evil.example"),
                    good.replacingOccurrences(of: "2.0.7.dmg", with: "2.0.8.dmg"),
                    good.replacingOccurrences(of: ".dmg", with: ".msi"),
                    good.replacingOccurrences(of: "Drumazon2", with: "PunchBox2")] {
            XCTAssertFalse(PluginDownloadPolicy.isAllowed(URL(string: bad)!, for: release()), bad)
        }
    }
    func testMissingDownloadDecodesFromOlderCatalogue() throws {
        let data = try JSONEncoder().encode(release())
        let decoded = try JSONDecoder().decode(PluginReleaseRecord.self, from: data)
        XCTAssertNil(decoded.downloadURL)
    }
    func testInvalidDownloadRejectsWholeCatalogue() throws {
        let snapshot = CatalogueSnapshot(schemaVersion: 1, sequence: 1, generatedOn: "2026-09-05",
            plugins: [release(download: good + "?token=secret")], daws: [], drivers: [], architectures: [], releaseNotes: [])
        XCTAssertThrowsError(try CatalogueValidator.validate(snapshot, now: EvidenceFreshness.date("2026-09-05")!))
    }
}
