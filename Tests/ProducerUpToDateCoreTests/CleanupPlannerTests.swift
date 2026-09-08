// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class CleanupPlannerTests: XCTestCase {
    func testOnlyBundlesAreEligibleAndAllSupportDataIsProtected() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try bundle(root.appendingPathComponent("Fixture.app"))
        for folder in ["Preferences/com.vendor.fixture.plist", "Application Support/com.vendor.fixture", "Caches/com.vendor.fixture", "Audio/Presets/Fixture", "Licences/Fixture"] {
            let url = root.appendingPathComponent("Library/" + folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let plan = CleanupPlanner(homeDirectory: root, allowedRoots: [root]).plan(for: daw(app))
        XCTAssertEqual(plan.items.map(\.path), [app])
        XCTAssertTrue(plan.excludedUserContentDescription.contains("licences"))
    }

    func testRejectsLinksChangedIdentityProtectedKindsAndOutsideRoots() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try bundle(root.appendingPathComponent("Fixture.app"))
        let safety = CleanupSafety(allowedRoots: [root])
        let item = CleanupItem(path: app, kind: .application)
        XCTAssertNil(safety.validate(item))
        XCTAssertNotNil(safety.validate(CleanupItem(path: app, kind: .applicationSupport)))
        XCTAssertNotNil(CleanupSafety(allowedRoots: [root.appendingPathComponent("Elsewhere")]).validate(item))
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        XCTAssertNotNil(safety.validate(CleanupItem(path: link, kind: .application)))
        try Data("changed".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNotNil(safety.validate(item))
        var moves = 0
        let result = CleanupExecutor.execute(CleanupPlan(displayName: "Fixture", items: [item], excludedUserContentDescription: ""), safety: safety) { _ in moves += 1 }
        XCTAssertEqual(moves, 0)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testRejectsNestedBundlesAndStopsOnMoveFailure() throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let app = try bundle(root.appendingPathComponent("Fixture.app"))
        let nested = try bundle(app.appendingPathComponent("Contents/Nested.app"))
        let safety = CleanupSafety(allowedRoots: [root])
        XCTAssertNotNil(safety.validate(CleanupItem(path: nested, kind: .application)))
        let second = try bundle(root.appendingPathComponent("Second.app"))
        let plan = CleanupPlan(displayName: "Fixture", items: [app, second].map { CleanupItem(path: $0, kind: .application) }, excludedUserContentDescription: "")
        var attempts = 0
        let result = CleanupExecutor.execute(plan, safety: safety) { _ in
            attempts += 1
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(result.movedCount, 0)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func bundle(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.vendor.fixture"], format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        return url
    }
    private func daw(_ app: URL) -> InstalledDAWRecord {
        InstalledDAWRecord(id: "fixture", definitionID: "fixture", name: "Fixture", vendor: "Vendor", bundleIdentifier: "../../Music", displayVersion: "1", buildVersion: nil, path: app, executablePath: nil, architectures: [])
    }
}

final class DriverCleanupPlanTests: XCTestCase {
    private func make(_ root: URL, _ relative: String, id: String) throws -> URL {
        let bundle = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        return bundle
    }
    private func record(_ url: URL, id: String?, kind: String) -> DriverRecord {
        DriverRecord(path: url, name: url.deletingPathExtension().lastPathComponent, bundleIdentifier: id, version: "1.0", kind: kind)
    }

    func testAllDriverPlansUseVendorInstructions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let hal = try make(root, "Library/Audio/Plug-Ins/HAL/ACE.driver", id: "com.rogueamoeba.ACE.driver")
        let midi = try make(root, "Library/Audio/MIDI Drivers/Iface.plugin", id: "com.example.iface")
        let apple = try make(root, "Library/Audio/Plug-Ins/HAL/ParrotAudioPlugin.driver", id: "com.apple.audio.ParrotAudioPlugin")
        let kext = try make(root, "Library/Extensions/Vendor.kext", id: "com.vendor.kext")
        let stray = try make(root, "Library/Audio/Plug-Ins/Components/Not.driver", id: "com.vendor.stray")
        let planner = CleanupPlanner(allowedRoots: [root.appendingPathComponent("Library/Audio/Plug-Ins"), root.appendingPathComponent("Library/Audio/MIDI Drivers")])
        XCTAssertEqual(planner.plan(for: record(hal, id: "com.rogueamoeba.ACE.driver", kind: "Core Audio driver")).items.map(\.kind), [])
        XCTAssertEqual(planner.plan(for: record(midi, id: "com.example.iface", kind: "MIDI driver")).items.count, 0)
        let applePlan = planner.plan(for: record(apple, id: "com.apple.audio.ParrotAudioPlugin", kind: "Core Audio driver"))
        XCTAssertTrue(applePlan.items.isEmpty)
        XCTAssertTrue(applePlan.excludedUserContentDescription.contains("part of macOS"))
        let kextPlan = planner.plan(for: record(kext, id: "com.vendor.kext", kind: "Audio system driver · declares IOAudioFamily"))
        XCTAssertTrue(kextPlan.items.isEmpty)
        XCTAssertTrue(kextPlan.excludedUserContentDescription.contains("Kernel and system extensions"))
        XCTAssertTrue(planner.plan(for: record(stray, id: "com.vendor.stray", kind: "Core Audio driver")).items.isEmpty, "A .driver outside the HAL folder is not eligible")
        let eligible = planner.plan(for: record(hal, id: "com.rogueamoeba.ACE.driver", kind: "Core Audio driver"))
        XCTAssertTrue(eligible.excludedUserContentDescription.contains("does not remove driver files"))
    }

    func testSafetyRefusesAppleComponentsEvenWhenPlannedDirectly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let apple = try make(root, "Library/Audio/Plug-Ins/HAL/ParrotAudioPlugin.driver", id: "com.apple.audio.ParrotAudioPlugin")
        let safety = CleanupSafety(allowedRoots: [root.appendingPathComponent("Library/Audio/Plug-Ins")])
        let forced = CleanupItem(path: apple, kind: .driverBundle)
        XCTAssertEqual(safety.validate(forced), "Don’t delete this: it is an Apple component installed with macOS.")
        let result = CleanupExecutor.execute(CleanupPlan(displayName: "x", items: [forced], excludedUserContentDescription: ""), safety: safety) { _ in XCTFail("must not move") }
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testDriverValidationRejectsLinksAndChangedBundles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let hal = try make(root, "Library/Audio/Plug-Ins/HAL/Real.driver", id: "com.vendor.real")
        let link = root.appendingPathComponent("Library/Audio/Plug-Ins/HAL/Alias.driver")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: hal)
        let planner = CleanupPlanner(allowedRoots: [root.appendingPathComponent("Library/Audio/Plug-Ins")])
        XCTAssertTrue(planner.plan(for: record(link, id: "com.vendor.real", kind: "Core Audio driver")).items.isEmpty)
        let item = CleanupItem(path: hal, kind: .driverBundle)
        try Data("changed".utf8).write(to: hal.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNotNil(planner.safety.validate(item), "A bundle that changed after preview is refused")
    }
}
