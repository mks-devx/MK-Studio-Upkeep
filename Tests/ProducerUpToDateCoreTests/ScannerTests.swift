// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class ScannerTests: XCTestCase {
    func testFilenameFallbackIsSanitisedWithoutChangingTheBundlePath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (filename, expected) in [("Fixture\u{202E}\u{200B} Synth\u{0007}", "Fixture Synth"), ("\u{202E}\u{200B}", "Plugin")] {
            let bundle = root.appendingPathComponent(filename + ".vst3")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let record = BundleMetadataReader().read(bundleURL: bundle, format: .vst3)
            XCTAssertEqual(record.name, expected)
            XCTAssertEqual(record.path, bundle, "Display sanitisation must preserve the actual filesystem location")
        }
    }

    func testScansNestedVST3BundleWithoutDescendingIntoBundle() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let pluginURL = temporaryRoot
            .appendingPathComponent("Vendor", isDirectory: true)
            .appendingPathComponent("Fixture.vst3", isDirectory: true)
        let executableURL = pluginURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("Fixture", isDirectory: false)
        let plistURL = pluginURL
            .appendingPathComponent("Contents/Info.plist", isDirectory: false)
        let moduleInfoURL = pluginURL
            .appendingPathComponent(
                "Contents/Resources/moduleinfo.json",
                isDirectory: false
            )

        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: moduleInfoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture",
            "CFBundleDisplayName": "Fixture Synth",
            "CFBundleExecutable": "Fixture",
            "CFBundleShortVersionString": "2.4.1",
            "CFBundleVersion": "2410"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)
        let moduleInfo: [String: Any] = [
            "Name": "Fixture Synth",
            "Version": "2.4.1",
            "Factory Info": [
                "Vendor": "Example Audio"
            ],
            "Classes": [
                [
                    "CID": "01234567-89AB-CDEF-0123-456789ABCDEF",
                    "Name": "Fixture Synth",
                    "Version": "2.4.1"
                ]
            ]
        ]
        let moduleInfoData = try JSONSerialization.data(
            withJSONObject: moduleInfo,
            options: [.sortedKeys]
        )
        try moduleInfoData.write(to: moduleInfoURL)

        var executableData = Data([0xCF, 0xFA, 0xED, 0xFE])
        executableData.append(contentsOf: [0x0C, 0x00, 0x00, 0x01])
        executableData.append(Data(repeating: 0, count: 24))
        try executableData.write(to: executableURL)

        let report = try PluginScanner(metadataReader: BundleMetadataReader(
            mac: MacArchitecture(processArchitecture: .arm64, translated: false))).scan(
            configuration: ScanConfiguration(
                locations: [
                    ScanLocation(url: temporaryRoot, format: .vst3)
                ]
            )
        )

        XCTAssertEqual(report.records.count, 1)
        let record = try XCTUnwrap(report.records.first)
        XCTAssertEqual(record.name, "Fixture Synth")
        XCTAssertEqual(record.displayVersion, "2.4.1")
        XCTAssertEqual(record.buildVersion, "2410")
        XCTAssertEqual(record.bundleIdentifier, "com.example.fixture")
        XCTAssertEqual(record.architectures, [.arm64])
        XCTAssertTrue(
            record.identifiers.contains(
                PluginIdentifier(
                    kind: .bundleIdentifier,
                    value: "com.example.fixture"
                )
            )
        )
        XCTAssertTrue(
            record.identifiers.contains(
                PluginIdentifier(
                    kind: .vst3Class,
                    value: "0123456789abcdef0123456789abcdef"
                )
            )
        )
        XCTAssertTrue(record.issues.isEmpty)
        let intelReport = try PluginScanner(metadataReader: BundleMetadataReader(
            mac: MacArchitecture(processArchitecture: .x86_64, translated: false))).scan(
                configuration: .init(locations: [.init(url: temporaryRoot, format: .vst3)]))
        let intelRecord = try XCTUnwrap(intelReport.records.first)
        XCTAssertEqual(intelRecord.architectures, [.arm64])
        XCTAssertEqual(intelRecord.issues.map(\.id), ["apple-silicon-only"],
            "An ARM-only plugin must remain a processor mismatch on an Intel Mac")
    }

    func testVST3ControllerDoesNotCreateFalseMultipleProductIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example.vst3")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.synth", "CFBundleName": "Example Synth", "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let processor: [String: Any] = ["CID": String(repeating: "A", count: 32), "Category": "Audio Module Class"]
        let controller: [String: Any] = ["CID": String(repeating: "B", count: 32), "Category": "Component Controller Class"]
        func read(_ classes: [[String: Any]]) throws -> NormalizedPluginProduct {
            let module: [String: Any] = ["Name": "Example Synth", "Factory Info": ["Vendor": "Example Audio"], "Classes": classes]
            try JSONSerialization.data(withJSONObject: module).write(to: resources.appendingPathComponent("moduleinfo.json"))
            let record = BundleMetadataReader().read(bundleURL: bundle, format: .vst3)
            return try XCTUnwrap(ProductNormalizer().normalize(records: [record]).products.first)
        }
        let single = try read([processor, controller])
        XCTAssertFalse(single.requiresVerification)
        XCTAssertEqual(single.bundles[0].identifiers.filter { $0.kind == .vst3Class }.count, 1)
        let second: [String: Any] = ["CID": String(repeating: "C", count: 32), "Category": "Audio Module Class"]
        XCTAssertTrue(try read([processor, controller, second]).requiresVerification, "Genuine multi-product containers still require review")
        let unclassified: [String: Any] = ["CID": String(repeating: "D", count: 32)]
        XCTAssertTrue(try read([processor, unclassified]).requiresVerification, "Missing category is not proof of a controller")
    }

    func testDeepVST3JSONFallsBackToBundleMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleName": "Fallback", "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        let json = "{\"Name\":\"Untrusted\",\"nested\":" + String(repeating: "[", count: 200) + "0" + String(repeating: "]", count: 200) + "}"
        try Data(json.utf8).write(to: resources.appendingPathComponent("moduleinfo.json"))
        XCTAssertEqual(BundleMetadataReader().read(bundleURL: root, format: .vst3).name, "Fallback")
    }

    func testBoundaryPluginIsReadAndDepthWarningIsAccurate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var parent = root
        for _ in 0..<PluginScanner.maximumDepth { parent.appendPathComponent("nested") }
        let bundle = parent.appendingPathComponent("Fixture.vst3")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let config = ScanConfiguration(locations: [ScanLocation(url: root, format: .vst3)])
        let complete = try PluginScanner().scan(configuration: config)
        XCTAssertEqual(complete.records.count, 1)
        XCTAssertNil(complete.locations.first?.errorDescription)
        try FileManager.default.createDirectory(at: parent.appendingPathComponent("More/Deep"), withIntermediateDirectories: true)
        let limited = try PluginScanner().scan(configuration: config)
        XCTAssertEqual(limited.records.count, 1)
        let warning = try XCTUnwrap(limited.locations.first?.errorDescription)
        XCTAssertTrue(warning.contains("search depth"))
        XCTAssertFalse(warning.contains("could not be read"))
    }

    func testExtractsAudioUnitComponentIdentity() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let pluginURL = temporaryRoot
            .appendingPathComponent("Fixture.component", isDirectory: true)
        let executableURL = pluginURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("Fixture", isDirectory: false)
        let plistURL = pluginURL
            .appendingPathComponent("Contents/Info.plist", isDirectory: false)

        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.fixture.component",
            "CFBundleName": "Fixture",
            "CFBundleExecutable": "Fixture",
            "CFBundleShortVersionString": "1.0.0",
            "AudioComponents": [
                [
                    "manufacturer": "Exmp",
                    "type": "aumu",
                    "subtype": "Fxtr",
                    "name": "Example Audio: Fixture",
                    "version": 65_536
                ]
            ]
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: plistURL)

        var executableData = Data([0xCF, 0xFA, 0xED, 0xFE])
        executableData.append(contentsOf: [0x0C, 0x00, 0x00, 0x01])
        executableData.append(Data(repeating: 0, count: 24))
        try executableData.write(to: executableURL)

        let record = BundleMetadataReader().read(
            bundleURL: pluginURL,
            format: .audioUnit
        )

        XCTAssertEqual(record.vendor, "Example Audio")
        XCTAssertTrue(
            record.identifiers.contains(
                PluginIdentifier(
                    kind: .audioUnitComponent,
                    value: "Exmp:aumu:Fxtr"
                )
            )
        )
        XCTAssertTrue(
            record.evidence.contains {
                $0.kind == .audioComponent
                    && $0.field == "AudioComponents[0].version"
                    && $0.value == "65536"
            }
        )
    }

    func testMissingLocationIsAnEmptySuccessfulLocation() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let report = try PluginScanner().scan(
            configuration: ScanConfiguration(
                locations: [
                    ScanLocation(url: missingURL, format: .clap)
                ]
            )
        )

        XCTAssertTrue(report.records.isEmpty)
        XCTAssertEqual(report.locations.first?.wasAccessible, true)
        XCTAssertEqual(report.locations.first?.discoveredCount, 0)
    }
}
