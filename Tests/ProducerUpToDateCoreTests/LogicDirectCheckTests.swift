// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class LogicDirectCheckTests: XCTestCase {
    let now = EvidenceFreshness.date("2026-09-05")!
    let page = "<h1>Logic Pro for Mac release notes</h1><h2>New in Logic Pro 12.3.1</h2><p>These release notes apply to both the one-time purchase and Apple Creator Studio versions of Logic Pro for Mac.</p><h2>Previous versions</h2><h3>Logic Pro for Mac 12.3</h3>"
    func observation(_ page: String) -> DirectVendorObservation { .init(vendor: .logic, checkedAt: now, page: page) }
    func testMacSourceRecognizesBothEditionsAndComparesInstalledVersion() throws {
        let release = try DirectVendorChecks.logicRelease(from: observation(page), now: now)
        XCTAssertEqual(release.latestVersion, "12.3.1")
        XCTAssertEqual(release.sourceURL, URL(string: "https://support.apple.com/en-us/109503"))
        for (version, expected) in [("12.3.1", UpdateCheckState.current), ("12.3", .updateAvailable), ("12.4", .unavailable)] {
            let installed = InstalledDAWRecord(id: "logic", definitionID: "logic-pro", name: "Logic Pro Creator Studio", vendor: "Apple", bundleIdentifier: "com.apple.mobilelogic", displayVersion: version, buildVersion: "6682", path: URL(fileURLWithPath: "/Applications/Logic.app"), executablePath: nil, architectures: [.arm64])
            XCTAssertEqual(DAWUpdateEvaluator.evaluate(installed, catalogue: [release], now: now).updateState, expected)
        }
        XCTAssertTrue(DAWScanConfiguration.standard.definitions.first { $0.id == "logic-pro" }!.bundleIdentifiers.contains("com.apple.mobilelogic"))
    }
    func testRejectsWrongPlatformAmbiguityAndMissingEditionScope() {
        for invalid in [page.replacingOccurrences(of: "for Mac", with: "for iPad"),
                        page + "<h2>New in Logic Pro 12.4</h2>",
                        page.replacingOccurrences(of: "Apple Creator Studio", with: "different edition"),
                        page.replacingOccurrences(of: "12.3.1", with: "12.4 beta")] {
            XCTAssertThrowsError(try DirectVendorChecks.logicRelease(from: observation(invalid), now: now))
        }
    }
    func testRejectsRegressionStaleAndWrongSource() throws {
        let newer = DAWReleaseRecord(definitionID: "logic-pro", latestVersion: "12.4", sourceURL: DirectVendor.logic.url, checkedOn: "2026-09-05")
        XCTAssertThrowsError(try DirectVendorChecks.logicRelease(from: observation(page), baseline: newer, now: now))
        XCTAssertThrowsError(try DirectVendorChecks.logicRelease(from: observation(page), now: now.addingTimeInterval(31 * 86_400)))
        XCTAssertThrowsError(try DirectVendorChecks.logicRelease(from: .init(vendor: .d16, checkedAt: now, page: page), now: now))
        XCTAssertEqual(DirectVendorChecks.overlay([observation(page)], baseline: []).count, 0)
    }
}
