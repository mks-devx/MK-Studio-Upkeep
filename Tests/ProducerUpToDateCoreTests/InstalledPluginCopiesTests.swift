// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class InstalledPluginCopiesTests: XCTestCase {
    private func record(_ id: String, name: String, format: PluginFormat, version: String, path: String) -> PluginBundleRecord {
        PluginBundleRecord(id: id, name: name, vendor: "Example Audio", format: format,
            bundleIdentifier: "com.example." + name.replacingOccurrences(of: " ", with: ""), displayVersion: version,
            buildVersion: nil, path: URL(fileURLWithPath: path), executablePath: nil,
            architectures: [.arm64], fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
    }
    func testDifferentEditionsRemainSeparateAndFormatsStayTogether() {
        let rows = [
            record("old", name: "Example Editor 10", format: .audioUnit, version: "10.0.1", path: "/synthetic/old.component"),
            record("au", name: "Example Editor 12", format: .audioUnit, version: "12.0.1", path: "/synthetic/new.component"),
            record("vst", name: "Example Editor 12", format: .vst3, version: "12.0.1", path: "/synthetic/new.vst3")
        ]
        let products = ProductNormalizer().normalize(records: rows).products
        XCTAssertEqual(products.count, 2)
        XCTAssertEqual(products.first { $0.name == "Example Editor 12" }?.formats, [.audioUnit, .vst3])
    }
    func testSameFormatCopiesPreserveLocationsAndDifferentVersions() throws {
        let rows = [
            record("one", name: "Example Synth", format: .audioUnit, version: "1.0", path: "/synthetic/system.component"),
            record("two", name: "Example Synth", format: .audioUnit, version: "1.1", path: "/synthetic/user.component"),
            record("three", name: "Example Synth", format: .vst3, version: "1.0", path: "/synthetic/synth.vst3")
        ]
        let product = try XCTUnwrap(ProductNormalizer().normalize(records: rows).products.first)
        let groups = InstalledPluginCopies.groups(for: product)
        XCTAssertEqual(groups.map(\.format), [.audioUnit, .vst3])
        XCTAssertEqual(groups[0].copies.count, 2)
        XCTAssertEqual(Set(groups[0].copies.compactMap(\.displayVersion)), ["1.0", "1.1"])
        XCTAssertEqual(groups.flatMap(\.copies).count, 3)
    }
    func testLocationLabelsRespectAccountAndDirectoryBoundaries() {
        let home = URL(fileURLWithPath: "/synthetic/account")
        XCTAssertEqual(InstalledPluginCopies.locationLabel(for: home.appendingPathComponent("Library/Audio/Plug-Ins/Components/Example.component"), home: home), "Your account")
        XCTAssertEqual(InstalledPluginCopies.locationLabel(for: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/Example.vst3"), home: home), "All users")
        XCTAssertEqual(InstalledPluginCopies.locationLabel(for: URL(fileURLWithPath: "/synthetic/account-two/Library/Audio/Plug-Ins/Example.component"), home: home), "Other location")
        XCTAssertEqual(InstalledPluginCopies.locationLabel(for: URL(fileURLWithPath: "/Library/Audio/Plug-Ins-Other/Example.vst3"), home: home), "Other location")
    }
}
