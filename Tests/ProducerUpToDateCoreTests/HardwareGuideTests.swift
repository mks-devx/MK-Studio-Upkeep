// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class HardwareGuideTests: XCTestCase {
    private func driver(_ name: String, id: String?, kind: String = "Core Audio driver", version: String? = "1.0") -> DriverRecord {
        DriverRecord(path: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/\(name).driver"), name: name, bundleIdentifier: id, version: version, kind: kind)
    }

    func testKnownDriversAreExplainedWithMakerAndRoute() {
        let apple = DriverDescription.describe(driver("ParrotAudioPlugin", id: "com.apple.audio.ParrotAudioPlugin"))
        XCTAssertTrue(apple.contains("not third-party drivers"), apple)
        XCTAssertTrue(apple.contains("Updates: macOS updates."), apple)
        XCTAssertEqual(DriverDescription.route(for: driver("ParrotAudioPlugin", id: "com.apple.audio.ParrotAudioPlugin")), "Part of macOS · updated with macOS")
        let ace = DriverDescription.describe(driver("ACE", id: "com.rogueamoeba.ACE.driver"))
        XCTAssertTrue(ace.contains("Rogue Amoeba"), ace)
        XCTAssertTrue(ace.contains("Audio Hijack, Loopback or SoundSource"), ace)
        XCTAssertEqual(DriverDescription.maker(of: driver("ACE", id: "com.rogueamoeba.ACE.driver")), "Rogue Amoeba")
        let antelope = DriverDescription.describe(driver("AntelopeUnifiedDriver", id: "com.antelopeaudio.driver.AntelopeUnifiedDriver", kind: "Audio system driver · declares IOAudioFamily"))
        XCTAssertTrue(antelope.hasPrefix("A system-level audio driver."), antelope)
        XCTAssertTrue(antelope.contains("Antelope Launcher"), antelope)
    }

    func testUnknownDriversStateWhatIsNotKnown() {
        let unknown = DriverDescription.describe(driver("Mystery", id: "com.example-vendor.mystery"))
        XCTAssertTrue(unknown.contains("no reviewed information"), unknown)
        XCTAssertTrue(unknown.contains("“example-vendor”"), unknown)
        XCTAssertEqual(DriverDescription.maker(of: driver("Mystery", id: "com.example-vendor.mystery")), "Maker “example-vendor”")
        XCTAssertEqual(DriverDescription.route(for: driver("Mystery", id: "com.example-vendor.mystery")), "No reviewed update route")
        let anonymous = DriverDescription.describe(driver("Nameless", id: nil))
        XCTAssertTrue(anonymous.contains("could not be determined"), anonymous)
        XCTAssertEqual(DriverDescription.maker(of: driver("Nameless", id: nil)), "Unknown maker")
        XCTAssertNil(DriverDescription.vendorLabel(from: "MIDI"))
        XCTAssertEqual(DriverDescription.vendorLabel(from: "jp.co.korg.driver"), "“korg”")
        let midi = DriverDescription.describe(driver("Iface", id: "com.example.iface", kind: "MIDI driver"))
        XCTAssertTrue(midi.hasPrefix("A Core MIDI driver."), midi)
    }

    func testManufacturerMatchingIsExactAndCaseInsensitive() {
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "Antelope Audio")?.updateRoute, "Antelope Launcher")
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "native instruments gmbh")?.vendor, "Native Instruments")
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "SAM")?.vendor, "Samsung")
        XCTAssertEqual(HardwareVendorGuide.matching(manufacturer: "Apple Inc.")?.updateRoute, "macOS updates")
        XCTAssertNil(HardwareVendorGuide.matching(manufacturer: "Antelope Audio Ltd"), "No substring guessing")
        XCTAssertNil(HardwareVendorGuide.matching(manufacturer: "Some Small Maker"))
        XCTAssertNil(HardwareVendorGuide.matching(manufacturer: ""))
        for entry in HardwareVendorGuide.entries {
            XCTAssertEqual(entry.guide.url?.scheme, "https", entry.guide.vendor)
            XCTAssertFalse(entry.guide.updateRoute.isEmpty, entry.guide.vendor)
        }
        XCTAssertEqual(HardwareVendorGuide.matching(bundleIdentifier: "com.rogueamoeba.ACE.driver")?.vendor, "Rogue Amoeba")
        XCTAssertNil(HardwareVendorGuide.matching(bundleIdentifier: nil))
    }

    func testProtectionIsRedForSystemComponentsExtensionsAndDependencies() {
        let interface = AudioHardwareRecord(id: 1, name: "Fixture Interface", manufacturer: "Antelope Audio", transport: "Thunderbolt")
        let speakers = AudioHardwareRecord(id: 2, name: "Built-in Speakers", manufacturer: "Apple Inc.", transport: "Built-in")
        let apple = DriverProtection.assess(driver("ParrotAudioPlugin", id: "com.apple.audio.ParrotAudioPlugin"), devices: [speakers])
        XCTAssertTrue(apple.isRed)
        XCTAssertEqual(apple.headline, "Don’t delete this")
        XCTAssertTrue(apple.reason?.contains("Part of macOS") == true)
        let kext = DriverRecord(path: URL(fileURLWithPath: "/Library/Extensions/AntelopeUnifiedDriver.kext"), name: "AntelopeUnifiedDriver",
                                bundleIdentifier: "com.antelopeaudio.driver.AntelopeUnifiedDriver", version: "4.6", kind: "Audio system driver · declares IOAudioFamily")
        let kextProtection = DriverProtection.assess(kext, devices: [interface, speakers])
        XCTAssertTrue(kextProtection.isRed)
        XCTAssertTrue(kextProtection.reason?.contains("Your Fixture Interface depends on it.") == true, kextProtection.reason ?? "")
        XCTAssertEqual(DriverProtection.dependents(of: kext, devices: [interface, speakers]), ["Fixture Interface"], "Built-in Apple audio is never a dependent")
        let halWithDevice = DriverProtection.assess(driver("SomeVendorHAL", id: "com.antelopeaudio.hal"), devices: [interface])
        XCTAssertTrue(halWithDevice.isRed)
        let ace = DriverProtection.assess(driver("ACE", id: "com.rogueamoeba.ACE.driver"), devices: [interface, speakers])
        XCTAssertFalse(ace.isRed)
        XCTAssertEqual(ace.headline, "Read before removing")
        XCTAssertTrue(DriverProtection.isSystemComponent(bundleIdentifier: nil, path: URL(fileURLWithPath: "/System/Library/Extensions/X.kext")))
        XCTAssertFalse(DriverProtection.isSystemComponent(bundleIdentifier: "com.applesauce.x", path: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/X.driver")), "Prefix match is on the identifier segment, not a loose substring")
    }

    func testSystemVirtualMIDIEntriesAreRecognised() {
        func midi(_ name: String, _ maker: String, offline: Bool? = false) -> MIDIHardwareRecord { .init(id: 1, name: name, manufacturer: maker, offline: offline) }
        XCTAssertTrue(midi("IAC Driver", "Apple Inc.").isSystemVirtual)
        XCTAssertTrue(midi("Network", "").isSystemVirtual)
        XCTAssertTrue(midi("UMP Network", "").isSystemVirtual)
        XCTAssertTrue(midi("Bluetooth", "Apple Inc.").isSystemVirtual)
        XCTAssertFalse(midi("Fixture Controller", "Ableton").isSystemVirtual)
        XCTAssertFalse(midi("Network", "Some Vendor").isSystemVirtual, "A hardware device named Network is not macOS")
        XCTAssertEqual(midi("Network", "").guide?.vendor, "Apple")
        XCTAssertEqual(midi("Fixture Keyboard", "Arturia").guide?.updateRoute, "Arturia Software Center and MIDI Control Center")
    }
}
