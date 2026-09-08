// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore
final class ManagerDirectoryTests: XCTestCase {
    func testExactVendorScopeAndMissingEvidence() {
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.arturia.Synth", "com.Arturia.Other"])?.name, "Arturia Software Center")
        for ids in [[], [""], ["com.arturia.Synth", ""], ["com.arturiafake.Synth"], ["com.arturia.Synth", "net.uvi.Other"]] {
            XCTAssertNil(ManagerDefinition.matching(identifiers: ids))
        }
    }
    func testCrossVendorAndLicenceToolsNeverClaimProductOwnership() {
        XCTAssertNil(ManagerDefinition.matching(identifiers: ["com.paceap.SomePlugin"]))
        XCTAssertNil(ManagerDefinition.matching(identifiers: ["com.pluginboutique.SomePlugin"]))
        XCTAssertEqual(Set(ManagerDefinition.known.map(\.id)).count, ManagerDefinition.known.count)
    }
    func testDocumentedAppNamesAndBrandingVariants() throws {
        let alliance = try XCTUnwrap(ManagerDefinition.known.first { $0.name == "Plugin Alliance Installation Manager" })
        XCTAssertTrue(alliance.appNames.contains("PA-InstallationManager"))
        let control = try XCTUnwrap(ManagerDefinition.known.first { $0.name == "Universal Control" })
        XCTAssertTrue(control.appNames.contains("Fender Universal Control"))
        let bridge = try XCTUnwrap(ManagerDefinition.known.first { $0.name == "Overbridge" })
        XCTAssertEqual(bridge.appNames.first, "Overbridge Control Panel")
        XCTAssertTrue(ManagerDefinition.known.allSatisfy { $0.id == $0.name })
        XCTAssertTrue(ManagerDefinition.known.allSatisfy { !$0.appNames.isEmpty })
    }

    func testRetiredProvenanceIsRejectedRatherThanRelabelled() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(ReleaseCheckMethod.self, from: Data("\"Retired package index\"".utf8)))
        XCTAssertEqual(try JSONDecoder().decode(ReleaseCheckMethod.self, from: Data("\"External reference\"".utf8)), .externalReference)
    }
}
