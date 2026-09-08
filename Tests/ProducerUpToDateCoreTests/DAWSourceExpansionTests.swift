// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class DAWSourceExpansionTests: XCTestCase {
    let now = EvidenceFreshness.date("2026-09-05")!
    func observation(_ vendor: DirectVendor, _ page: String) -> DirectVendorObservation { .init(vendor: vendor, checkedAt: now, page: page) }
    func testLive12VersionAndFamilyGuard() throws {
        let page = "<h1>Live 12 Release Notes</h1><h2>12.4.5 Release Notes</h2><h2>12.4.3 Release Notes</h2>"
        let release = try DirectVendorChecks.dawRelease(from: observation(.live, page), now: now)
        XCTAssertEqual(release.latestVersion, "12.4.5")
        XCTAssertEqual(release.majorVersion, 12)
        let old = InstalledDAWRecord(id: "live", definitionID: "ableton-live", name: "Live", vendor: "Ableton", bundleIdentifier: "com.ableton.live", displayVersion: "11.3.0", buildVersion: nil, path: URL(fileURLWithPath: "/Applications/Live.app"), executablePath: nil, architectures: [])
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(old, catalogue: [release], now: now).updateState, .notChecked)
        XCTAssertNil(DAWUpdateSource.checker(for: old))
        XCTAssertThrowsError(try DirectVendorChecks.dawRelease(from: observation(.live, page.replacingOccurrences(of: "12.4.3", with: "12.4.6")), now: now))
    }
    func testGarageBandRejectsIOSPage() throws {
        let page = "<h1>GarageBand for macOS release notes</h1><h2>New in GarageBand 10.4.15</h2>"
        XCTAssertEqual(try DirectVendorChecks.dawRelease(from: observation(.garageband, page), now: now).latestVersion, "10.4.15")
        XCTAssertThrowsError(try DirectVendorChecks.dawRelease(from: observation(.garageband, page.replacingOccurrences(of: "macOS", with: "iOS")), now: now))
    }
    func testReaperRequiresMatchingMacInstaller() throws {
        let page = "<h1>Download and Evaluate REAPER for Free</h1><div class='hdrbottom'>Version 7.79: August 17, 2026</div><h2>macOS</h2><a href='files/7.x/reaper779_universal.dmg'>Download</a>"
        XCTAssertEqual(try DirectVendorChecks.dawRelease(from: observation(.reaper, page), now: now).latestVersion, "7.79")
        for invalid in [page.replacingOccurrences(of: "reaper779", with: "reaper778"), page.replacingOccurrences(of: "macOS", with: "Windows"), page.replacingOccurrences(of: "files/7.x/", with: "https://untrusted.example/")] {
            XCTAssertThrowsError(try DirectVendorChecks.dawRelease(from: observation(.reaper, invalid), now: now))
        }
    }
    func testEveryKnownDAWHasOfficialFallbackButUnknownHasNone() {
        XCTAssertEqual(Set(DAWDefinition.known.map(\.id)).count, DAWDefinition.known.count)
        for daw in DAWDefinition.known { XCTAssertEqual(DAWUpdateSource.destination(for: daw.id)?.scheme, "https", daw.id) }
        XCTAssertNil(DAWUpdateSource.destination(for: "untrusted"))
    }
    func testInferredIdentitiesDoNotEnableChecks() {
        let inferred = InstalledDAWRecord(id: "test", definitionID: "reaper", name: "REAPER", vendor: "Cockos", bundleIdentifier: nil, displayVersion: "7.0", buildVersion: nil, path: URL(fileURLWithPath: "/Applications/REAPER.app"), executablePath: nil, architectures: [], identityIsInferred: true)
        XCTAssertNil(DAWUpdateSource.checker(for: inferred))
    }
}
