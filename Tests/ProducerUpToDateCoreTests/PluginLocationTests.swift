// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class PluginLocationTests: XCTestCase {
    func testAllFormatsAndSameFormatCopiesRemainAddressable() {
        func record(_ path: String, _ format: PluginFormat) -> PluginBundleRecord {
            .init(id: "same-identity", name: "Fixture", vendor: "Example", format: format,
                  bundleIdentifier: "org.example.fixture", displayVersion: "1", buildVersion: nil,
                  path: URL(fileURLWithPath: path), executablePath: nil, architectures: [],
                  fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        }
        let records = [record("/fixture/system/Test.component", .audioUnit),
                       record("/fixture/system/Test.vst3", .vst3),
                       record("/fixture/system/Test.vst", .vst2),
                       record("/fixture/user/Test.vst3", .vst3)]
        let copies = PluginBundleRecord.distinctInstalledCopies(records + [records[0]])
        XCTAssertEqual(copies.count, 4)
        XCTAssertEqual(Set(copies.map(\.path)), Set(records.map(\.path)))
        XCTAssertEqual(copies.filter { $0.format == .vst3 }.count, 2)
        XCTAssertEqual(copies.map(\.path), PluginBundleRecord.distinctInstalledCopies(records.reversed()).map(\.path))
    }
}
