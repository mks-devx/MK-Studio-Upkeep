// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class DriverAndManagerTests: XCTestCase {
    func testManagerSuggestionsRequireConsistentVendorIdentity() {
        XCTAssertEqual(VendorManager.matching(identifiers: ["com.native-instruments.Maschine 3"])?.name, "Native Access")
        XCTAssertEqual(VendorManager.matching(identifiers: ["com.ikmultimedia.t-racks"])?.name, "IK Product Manager")
        XCTAssertNil(VendorManager.matching(identifiers: ["com.native-instruments.fake", "com.other.product"]))
        XCTAssertNil(VendorManager.matching(identifiers: []))
        XCTAssertNil(VendorManager.matching(identifiers: ["com.ikmultimediaEvil.product"]))
    }

    func testDriverComparisonIsExactFreshAndDoesNotClaimCompatibility() throws {
        let catalogue = SyntheticCatalogueFixture.snapshot.drivers
        let current = DriverRecord(path: URL(fileURLWithPath: "/Library/Extensions/Fixture.kext"), name: "Fixture", bundleIdentifier: "com.example.driver", version: "2.0", kind: "Driver")
        let older = DriverRecord(path: current.path, name: current.name, bundleIdentifier: current.bundleIdentifier, version: "1.0", kind: current.kind)
        let unknown = DriverRecord(path: current.path, name: current.name, bundleIdentifier: "com.unreviewed.driver", version: "2.0", kind: current.kind)
        let now = EvidenceFreshness.date("2026-09-05")!
        XCTAssertEqual(DriverUpdateEvaluator.evaluate(current, catalogue: catalogue, now: now), .current)
        XCTAssertEqual(DriverUpdateEvaluator.evaluate(older, catalogue: catalogue, now: now), .updateAvailable)
        XCTAssertEqual(DriverUpdateEvaluator.evaluate(unknown, catalogue: catalogue, now: now), .notChecked)
        XCTAssertEqual(DriverUpdateEvaluator.evaluate(current, catalogue: catalogue, now: EvidenceFreshness.date("2027-01-01")!), .unavailable)
    }

    func testAudioScopeExcludesUnrelatedAndNameOnlyMatches() {
        let path = URL(fileURLWithPath: "/Library/SystemExtensions/Fixture.systemextension")
        for id in ["com.example.vpn.network", "com.vendor.storage", "com.audio.fake", "com.antelopeaudio.driver.AntelopeUnifiedDriverFake"] {
            XCTAssertNil(HardwareScanner.audioDriverKind(path: path, properties: ["CFBundleIdentifier": id, "CFBundleName": "Audio MIDI Driver"]))
        }
        XCTAssertNotNil(HardwareScanner.audioDriverKind(path: path, properties: ["IOKitPersonalities": ["device": ["IOUserClass": "IOUserAudioDriver"]]]))
        XCTAssertNotNil(HardwareScanner.audioDriverKind(path: path, properties: ["OSBundleLibraries": ["com.apple.iokit.IOAudioFamily": "1.0"]]))
        XCTAssertNotNil(HardwareScanner.audioDriverKind(path: path, properties: ["CFBundleIdentifier": "com.antelopeaudio.driver.AntelopeUnifiedDriver"]))
    }

    func testDedicatedAudioAndMIDILocationsEstablishScope() {
        XCTAssertNotNil(HardwareScanner.audioDriverKind(path: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/Fixture.driver"), properties: [:]))
        XCTAssertNotNil(HardwareScanner.audioDriverKind(path: URL(fileURLWithPath: "/Library/Audio/MIDI Drivers/Fixture.plugin"), properties: [:]))
        XCTAssertNil(HardwareScanner.audioDriverKind(path: URL(fileURLWithPath: "/Library/Other/Fixture.driver"), properties: [:]))
    }

    func testDriverScannerHandlesMalformedBundlesAndNeverDescendsIntoDrivers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Fixture.kext/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Nested.kext"), withIntermediateDirectories: true)
        try Data("bad plist".utf8).write(to: contents.appendingPathComponent("Info.plist"))
        let report = try HardwareScanner.scanDrivers(roots: [root, root])
        XCTAssertEqual(report.records.count, 0)
        XCTAssertNil(report.records.first?.version)
        XCTAssertEqual(report.warnings.count, 0)
    }
}
