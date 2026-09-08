// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class ExpandedPluginSourceTests: XCTestCase {
    let now = EvidenceFreshness.date("2026-09-05")!
    func record(_ name: String, _ version: String, _ vendor: DirectVendor) -> PluginReleaseRecord {
        .init(vendorIdentifierPrefixes: [vendor.prefix], productAliases: [name], latestVersion: version, sourceURL: vendor.url, checkedOn: "2026-09-01")
    }
    func testFabFilterRequiresExactProductMacVersionAgreement() throws {
        let page = #"<h2>Download FabFilter Pro-Q 4</h2><p>Equalizer<br>4.13 &mdash; Jun 25, 2026</p><a href="https://cdn-b.fabfilter.com/downloads/ffproq413.dmg">Download for macOS</a>"#
        let baseline = [record("Pro-Q 4", "4.12", .fabfilter), record("Pro-Q 3", "3.29", .fabfilter)]
        let observation = DirectVendorObservation(vendor: .fabfilter, checkedAt: now, page: page)
        let result = try DirectVendorChecks.records(from: observation, baseline: baseline, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.latestVersion, "4.13")
        XCTAssertNil(result.first?.downloadURL)
        let overlay = DirectVendorChecks.overlay([observation], baseline: baseline, now: now)
        XCTAssertEqual(overlay[1], baseline[1], "Older major editions must keep their original evidence")
        for invalid in [page + page, page.replacingOccurrences(of: "ffproq413", with: "ffproq412"), page.replacingOccurrences(of: "Download for macOS", with: "Download for Windows"), page.replacingOccurrences(of: "cdn-b.fabfilter.com", with: "spoof.example")] {
            XCTAssertThrowsError(try DirectVendorChecks.records(from: .init(vendor: .fabfilter, checkedAt: now, page: invalid), baseline: baseline, now: now))
        }
    }
    func testTDRFreeEditionDoesNotRenewGEOrOtherProducts() throws {
        let page = #"Latest version: <strong>2.2.2</strong><a href="https://www.tokyodawn.net/labs/Nova/2.2.2/TDR Nova.zip" title="Download TDR Nova - Mac Package">Macos Package</a>"#
        let baseline = [record("TDR Nova", "2.2.1", .tdrNova), record("TDR Nova GE", "2.2.0", .tdrNova)]
        let observation = DirectVendorObservation(vendor: .tdrNova, checkedAt: now, page: page)
        let result = DirectVendorChecks.overlay([observation], baseline: baseline, now: now)
        XCTAssertEqual(result[0].latestVersion, "2.2.2")
        XCTAssertEqual(result[1], baseline[1])
        for invalid in [page + page, page.replacingOccurrences(of: "/2.2.2/", with: "/2.2.1/"), page.replacingOccurrences(of: "Mac Package", with: "Windows Installer"), page.replacingOccurrences(of: "TDR Nova.zip", with: "TDR Nova GE.zip")] {
            XCTAssertThrowsError(try DirectVendorChecks.records(from: .init(vendor: .tdrNova, checkedAt: now, page: invalid), baseline: baseline, now: now))
        }
    }
    func testNewSourcesRetainEvidenceAfterRegressionOrStaleness() {
        let page = #"Latest version: <strong>2.2.2</strong><a href="https://www.tokyodawn.net/labs/Nova/2.2.2/TDR Nova.zip" title="Download TDR Nova - Mac Package">Macos Package</a>"#
        let baseline = [record("TDR Nova", "2.2.3", .tdrNova)]
        for date in [now, now.addingTimeInterval(-31 * 86400)] {
            XCTAssertEqual(DirectVendorChecks.overlay([.init(vendor: .tdrNova, checkedAt: date, page: page)], baseline: baseline, now: now), baseline)
        }
    }
}
