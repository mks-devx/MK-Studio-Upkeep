// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class ManagerSeedTests: XCTestCase {
    func testManagersCoverVendorsBeyondTheSeedFixtures() {
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.waves.plugins.x", "com.waves.plugins.y"])?.name, "Waves Central")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.softube.console1"])?.name, "Softube Central")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.meldaproduction.mautopan"])?.name, "MPluginManager")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.focusrite.x"])?.name, "Focusrite Control 2")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.uaudio.uad"])?.name, "UA Connect")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.presonus.studioone"])?.name, "Universal Control")
        XCTAssertEqual(ManagerDefinition.matching(identifiers: ["com.akaipro.mpc"])?.name, "inMusic Software Center")
        XCTAssertNil(ManagerDefinition.matching(identifiers: ["com.waves.x", "com.softube.y"]), "Mixed vendors never resolve to one manager")
        XCTAssertNil(ManagerDefinition.matching(identifiers: ["com.nobody.x"]))
        let ids = ManagerDefinition.known.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Manager identities are unique")
        XCTAssertTrue(ManagerDefinition.known.allSatisfy { $0.url?.scheme == "https" })
        XCTAssertGreaterThanOrEqual(ManagerDefinition.known.count, 25)
    }

    func testHardwareGuideUsesNamesWithoutUnverifiedManagerIdentifiers() {
        XCTAssertNil(HardwareVendorGuide.matching(manufacturer: "Focusrite")?.managerBundleIdentifier)
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "Focusrite")?.managerAppName, "Focusrite Control 2")
        XCTAssertNil(HardwareVendorGuide.matching(manufacturer: "Universal Audio")?.managerBundleIdentifier)
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "Universal Audio")?.managerAppName, "UA Connect")
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "RØDE Microphones")?.managerAppName, "RØDE Central")
        XCTAssertEqual(HardwareVendorGuide.matching(bundleIdentifier: "org.softube.driver")?.vendor, "Softube")
        for entry in HardwareVendorGuide.entries where entry.guide.managerBundleIdentifier != nil {
            XCTAssertNotNil(entry.guide.managerAppName, "\(entry.guide.vendor) has an identifier but no app name for the fallback")
        }
    }
}
