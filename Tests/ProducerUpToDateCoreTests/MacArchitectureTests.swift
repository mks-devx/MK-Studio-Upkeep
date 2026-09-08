// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class MacArchitectureTests: XCTestCase {
    func testTranslatedIntelProcessStillIdentifiesAppleSiliconHardware() {
        let mac = MacArchitecture(processArchitecture: .x86_64, translated: true)
        XCTAssertEqual(mac.processor, .appleSilicon)
        XCTAssertEqual(mac.scannerIsTranslated, true)
        XCTAssertEqual(MacArchitecture(processArchitecture: .x86_64, translated: false).processor, .intel)
        XCTAssertEqual(MacArchitecture(processArchitecture: .arm64, translated: false).processor, .appleSilicon)
    }

    func testFailedTranslationProbeDoesNotGuessIntelHardware() {
        XCTAssertEqual(MacArchitecture(processArchitecture: .x86_64, translated: nil).processor, .unknown)
        XCTAssertEqual(MacArchitecture(processArchitecture: .unknown, translated: nil).processor, .unknown)
        XCTAssertEqual(MacArchitecture(processArchitecture: .arm64, translated: nil).processor, .appleSilicon)
    }

    func testClassificationDoesNotCallAnUnrecognisedSliceIntelOnly() {
        XCTAssertEqual(InstalledArchitecture.classify([.x86_64, .unknown]), .unknown)
        XCTAssertEqual(InstalledArchitecture.classify([]), .unknown)
        XCTAssertEqual(InstalledArchitecture.classify([.arm64, .x86_64]), .universal)
        XCTAssertEqual(InstalledArchitecture.classify([.x86_64, .i386]), .intel64)
        XCTAssertEqual(InstalledArchitecture.classify([.arm64]), .appleSilicon)
        XCTAssertEqual(InstalledArchitecture.classify([.i386]), .legacy32)
    }

    func testReaderFlagsIntelPluginEvenWhenScannerIsTranslated() throws {
        let translated = MacArchitecture(processArchitecture: .x86_64, translated: true)
        let intel = MacArchitecture(processArchitecture: .x86_64, translated: false)
        let arm = MacArchitecture(processArchitecture: .arm64, translated: false)
        try withBundle(cpu: 0x0100_0007) { url in
            for mac in [translated, arm] {
                XCTAssertTrue(BundleMetadataReader(mac: mac).read(bundleURL: url, format: .audioUnit)
                    .issues.contains { $0.id == "intel-only" })
            }
            XCTAssertFalse(BundleMetadataReader(mac: intel).read(bundleURL: url, format: .audioUnit)
                .issues.contains { $0.id == "intel-only" })
        }
    }

    func testReaderFlagsArmOnlyPluginOnIntelAndUnknownCPUSeparately() throws {
        let intel = MacArchitecture(processArchitecture: .x86_64, translated: false)
        try withBundle(cpu: 0x0100_000C) { url in
            let issues = BundleMetadataReader(mac: intel).read(bundleURL: url, format: .vst3).issues
            XCTAssertTrue(issues.contains { $0.id == "apple-silicon-only" && $0.severity == .critical })
        }
        try withBundle(cpu: 0x0100_FFFF) { url in
            let issues = BundleMetadataReader(mac: intel).read(bundleURL: url, format: .vst3).issues
            XCTAssertTrue(issues.contains { $0.id == "unknown-architecture" })
            XCTAssertFalse(issues.contains { $0.id == "intel-only" || $0.id == "apple-silicon-only" })
        }
    }

    func testHostGuidanceRequiresApplicableHostAndFormat() {
        let now = EvidenceFreshness.date("2026-09-05")!
        XCTAssertNil(RosettaHostGuidance.guidance(host: .logic, formats: [.vst3], now: now))
        XCTAssertNil(RosettaHostGuidance.guidance(host: .live, formats: [.clap], now: now))
        XCTAssertNil(RosettaHostGuidance.guidance(host: .other, formats: [.audioUnit], now: now))
        let au = RosettaHostGuidance.guidance(host: .live, formats: [.audioUnit], now: now)!
        XCTAssertTrue(au.detail.contains("Audio Units"))
        XCTAssertFalse(au.detail.contains("VST2/VST3"))
        let vst = RosettaHostGuidance.guidance(host: .live, formats: [.vst3], now: now)!
        XCTAssertTrue(vst.detail.contains("VST2/VST3"))
        XCTAssertFalse(vst.detail.contains("Audio Units"))
        XCTAssertTrue(RosettaHostGuidance.guidance(host: .logic, formats: [.audioUnit], now: now)!.detail.contains("ARA"))
    }

    func testStaleHostGuidanceWithdrawsInstructionsAndKeepsOfficialSource() {
        let guidance = RosettaHostGuidance.guidance(host: .live, formats: [.vst3],
            now: EvidenceFreshness.date("2026-12-05")!)!
        XCTAssertFalse(guidance.isFresh)
        XCTAssertFalse(guidance.detail.contains("opening Live through Rosetta"))
        XCTAssertEqual(guidance.sourceURL.host, "help.ableton.com")
    }

    private func withBundle(cpu: UInt32, inspect: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("Fixture.component")
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "test.fixture",
                     "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        var data = Data([0xCF, 0xFA, 0xED, 0xFE])
        data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: cpu >> ($0 * 8)) })
        data.append(Data(repeating: 0, count: 24))
        try data.write(to: macOS.appendingPathComponent("Fixture"))
        try inspect(bundle)
    }
}
