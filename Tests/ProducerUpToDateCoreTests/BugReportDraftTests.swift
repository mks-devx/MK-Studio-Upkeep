// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class BugReportDraftTests: XCTestCase {
    func testNoScanIsNotReportedAsEmptyScan() {
        let d = BugReportDraft.Diagnostics(appVersion: "0.0.0", system: "Example OS", processor: "Example processor",
                                          pluginFiles: 0, dawApplications: 0, inaccessibleLocations: 0, scanPerformed: false)
        let body = BugReportDraft.body(description: "Test", diagnostics: d)
        XCTAssertTrue(body.contains("No completed scan"))
        XCTAssertFalse(body.contains("Plugin files found"))
    }
    func testOptOutContainsOnlyUserDescription() {
        XCTAssertEqual(BugReportDraft.body(description: "A button stopped responding.", diagnostics: nil),
                       "## What happened\n\nA button stopped responding.")
    }
    func testQueryRoundTripAndNoExtraParameters() throws {
        let body = BugReportDraft.body(description: "A & B? #test\nΕλληνικά 🎵 + =", diagnostics: nil)
        let url = try XCTUnwrap(BugReportDraft.formURL(body: body))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/mks-devx/MK-Studio-Upkeep/issues/new")
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "body" })?.value, body)
    }
    func testOverlongReportRefusedWithoutTruncation() {
        XCTAssertNil(BugReportDraft.formURL(body: String(repeating: "a", count: 6001)))
        XCTAssertNil(BugReportDraft.formURL(body: String(repeating: "🎵", count: 1000)))
    }
    func testDiagnosticsAreExplicitAndBounded() {
        let d = BugReportDraft.Diagnostics(appVersion: "0.0.0", system: "Example OS", processor: "Example processor",
                                          pluginFiles: -10, dawApplications: 2, inaccessibleLocations: 1)
        let body = BugReportDraft.body(description: "Test", diagnostics: d)
        XCTAssertTrue(body.contains("Plugin files found: 0"))
        XCTAssertTrue(body.contains("DAW applications found: 2"))
        XCTAssertFalse(body.contains("/Users/"))
    }
}
