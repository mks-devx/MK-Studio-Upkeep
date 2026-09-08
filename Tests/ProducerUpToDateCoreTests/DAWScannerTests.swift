// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore
@testable import MaintainerCatalogueSupport

final class DAWScannerTests: XCTestCase {
    func testApplicationFilenameIsSanitisedWithoutChangingItsPathOrIdentity() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = DAWDefinition(id: "fixture", name: "Fixture DAW", vendor: "Example",
            bundleIdentifiers: ["com.example.fixture"], applicationNamePrefixes: [])
        let names = [("Fixture\u{202E}\u{200B} DAW\u{0007}", "Fixture DAW"), ("\u{202E}\u{200B}", "Metadata Name")]
        for (filename, _) in names {
            try makeApplication(in: root, folderName: filename + ".app", bundleIdentifier: "com.example.fixture",
                displayName: "Metadata Name", version: "1.0")
        }
        let records = try DAWScanner().scan(configuration: .init(applicationRoots: [root], definitions: [definition]))
        XCTAssertEqual(records.count, names.count)
        for (filename, expected) in names {
            let path = root.appendingPathComponent(filename + ".app", isDirectory: true)
            let record = try XCTUnwrap(records.first { $0.path.lastPathComponent == path.lastPathComponent })
            XCTAssertEqual(record.path.resolvingSymlinksInPath().path, path.resolvingSymlinksInPath().path)
            XCTAssertEqual(record.name, expected)
            XCTAssertEqual(record.bundleIdentifier, "com.example.fixture")
            XCTAssertFalse(record.identityIsInferred)
        }
    }

    func testFindsKnownDAWByBundleIdentifier() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeApplication(
            in: root,
            folderName: "Custom Name.app",
            bundleIdentifier: "test.vendor.daw",
            displayName: "Custom Name",
            version: "4.2.1"
        )
        let definition = DAWDefinition(
            id: "fixture-daw",
            name: "Fixture DAW",
            vendor: "Fixture Vendor",
            bundleIdentifiers: ["test.vendor.daw"],
            applicationNamePrefixes: []
        )

        let records = try DAWScanner().scan(
            configuration: DAWScanConfiguration(
                applicationRoots: [root],
                definitions: [definition]
            )
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].definitionID, "fixture-daw")
        XCTAssertEqual(records[0].displayVersion, "4.2.1")
        XCTAssertEqual(records[0].updateState, .notChecked)
    }

    func testFindsVersionedDAWByNamePrefix() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeApplication(
            in: root,
            folderName: "Ableton Live 14 Suite.app",
            bundleIdentifier: "fixture.unknown",
            displayName: "Ableton Live 14 Suite",
            version: "14.0.2"
        )
        let definition = DAWDefinition(
            id: "ableton-live",
            name: "Ableton Live",
            vendor: "Ableton",
            bundleIdentifiers: [],
            applicationNamePrefixes: ["Ableton Live"]
        )

        let records = try DAWScanner().scan(
            configuration: DAWScanConfiguration(
                applicationRoots: [root],
                definitions: [definition]
            )
        )

        XCTAssertEqual(records.map(\.name), ["Ableton Live 14 Suite"])
        XCTAssertTrue(records[0].identityIsInferred)
        let release = DAWReleaseRecord(definitionID: "ableton-live", latestVersion: "15.0", sourceURL: URL(string: "https://www.ableton.com/en/release-notes/live-12/")!, checkedOn: EvidenceFreshness.day(Date()))
        XCTAssertEqual(DAWUpdateEvaluator.evaluate(records[0], catalogue: [release]).updateState, .unavailable)
        XCTAssertTrue(CleanupPlanner(allowedRoots: [root]).plan(for: records[0]).items.isEmpty)
    }

    func testIgnoresUnrelatedApplications() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeApplication(
            in: root,
            folderName: "Notes.app",
            bundleIdentifier: "test.notes",
            displayName: "Notes",
            version: "1.0"
        )

        let records = try DAWScanner().scan(
            configuration: DAWScanConfiguration(
                applicationRoots: [root],
                definitions: DAWDefinition.known
            )
        )
        XCTAssertTrue(records.isEmpty)
    }

    func testExcludesCompanionsAndPrefixCollisions() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, id) in [("Reason Companion", "com.reasonstudios.nautilus"), ("Reason Rack Plugin", "fixture.rack"), ("Reasonable Editor", "fixture.editor"), ("Ableton Live Installer", "fixture.installer")] {
            try makeApplication(in: root, folderName: name + ".app", bundleIdentifier: id, displayName: name, version: "1.0")
        }
        XCTAssertTrue(try DAWScanner().scan(configuration: .init(applicationRoots: [root], definitions: DAWDefinition.known)).isEmpty)
    }

    func testReasonBundleIdentityAndRawBuildArePreserved() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApplication(in: root, folderName: "Reason 14.app", bundleIdentifier: "se.propellerheads.reason", displayName: "Reason", version: "14.1d1 build 10000")
        let records = try DAWScanner().scan(configuration: .init(applicationRoots: [root], definitions: DAWDefinition.known))
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records[0].identityIsInferred)
        XCTAssertEqual(records[0].displayVersion, "14.1d1 build 10000")
    }

    func testAppStoreReceiptRoutesUpdatesToTheStoreWithoutAppleWebReads() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApplication(in: root, folderName: "Logic Pro Creator Studio.app", bundleIdentifier: "com.apple.mobilelogic", displayName: "Logic Pro", version: "12.3.1")
        try makeApplication(in: root, folderName: "REAPER.app", bundleIdentifier: "com.cockos.reaper", displayName: "REAPER", version: "7.79")
        let receiptFolder = root.appendingPathComponent("Logic Pro Creator Studio.app/Contents/_MASReceipt", isDirectory: true)
        try FileManager.default.createDirectory(at: receiptFolder, withIntermediateDirectories: true)
        try Data([0x30, 0x82]).write(to: receiptFolder.appendingPathComponent("receipt"))
        // A receipt directory or symlink is not a receipt file.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("REAPER.app/Contents/_MASReceipt/receipt"), withIntermediateDirectories: true)

        let records = try DAWScanner().scan(configuration: .init(applicationRoots: [root], definitions: DAWDefinition.known))
        let logic = try XCTUnwrap(records.first { $0.definitionID == "logic-pro" })
        let reaper = try XCTUnwrap(records.first { $0.definitionID == "reaper" })
        XCTAssertTrue(logic.installedFromAppStore)
        XCTAssertFalse(reaper.installedFromAppStore)
        XCTAssertNil(DAWUpdateSource.checker(for: logic), "Apple's pages are not requested by the app")
        XCTAssertEqual(DAWUpdateSource.checker(for: logic, includeInactive: true), .logic)
        let store = try XCTUnwrap(DAWUpdateSource.appStoreDestination(for: logic))
        XCTAssertEqual(store.updates.absoluteString, "macappstore://showUpdatesPage")
        XCTAssertEqual(store.product?.absoluteString, "macappstore://apps.apple.com/app/id634148309")
        XCTAssertNil(DAWUpdateSource.appStoreDestination(for: reaper))
        XCTAssertNil(DAWUpdateSource.checker(for: reaper), "No live update reader is enabled")
        XCTAssertTrue(DAWUpdateEvaluator.evaluate(logic, catalogue: []).installedFromAppStore)
        XCTAssertTrue(logic.withoutUpdateEvidence().installedFromAppStore)
        let inferred = InstalledDAWRecord(id: "x", definitionID: "logic-pro", name: "Logic Pro", vendor: "Apple", bundleIdentifier: nil, displayVersion: "12.3", buildVersion: nil, path: logic.path, executablePath: nil, architectures: [], identityIsInferred: true, installedFromAppStore: true)
        XCTAssertNil(DAWUpdateSource.appStoreDestination(for: inferred)?.product, "A guessed identity must not link a product page")
        XCTAssertNotNil(DAWUpdateSource.appStoreDestination(for: inferred)?.updates)
    }

    func testBoundaryApplicationIsDetectedWithoutDescendingIntoIt() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var parent = root
        for _ in 0..<DAWScanner.maximumDepth { parent.appendPathComponent("nested") }
        try makeApplication(in: parent, folderName: "Fixture.app", bundleIdentifier: "test.vendor.daw", displayName: "Fixture", version: "1.0")
        let definition = DAWDefinition(id: "fixture", name: "Fixture", vendor: "Example", bundleIdentifiers: ["test.vendor.daw"], applicationNamePrefixes: [])
        let result = try DAWScanner().scanReport(configuration: .init(applicationRoots: [root], definitions: [definition]))
        XCTAssertEqual(result.records.count, 1)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testDepthLimitsAreScopeNotesWithoutHidingLibraryFolders() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var parent = root.appendingPathComponent("Library")
        for _ in 1..<DAWScanner.maximumDepth { parent.appendPathComponent("nested") }
        for leaf in ["First", "Second"] {
            try FileManager.default.createDirectory(at: parent.appendingPathComponent(leaf), withIntermediateDirectories: true)
        }
        let result = try DAWScanner().scanReport(configuration: .init(applicationRoots: [root], definitions: []))
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.scopeNotes.count, 1)
        let warning = try XCTUnwrap(result.scopeNotes.first)
        XCTAssertTrue(warning.contains("2 nested folders"))
        XCTAssertTrue(warning.contains(parent.appendingPathComponent("First").path))
        XCTAssertTrue(warning.contains(parent.appendingPathComponent("Second").path))
    }

    func testInvalidApplicationRootRemainsAWarning() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Applications")
        try Data("fixture".utf8).write(to: file)
        let result = try DAWScanner().scanReport(configuration: .init(applicationRoots: [file], definitions: []))
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.scopeNotes.isEmpty)
    }

    func testApplicationBeyondDepthLimitRemainsExcludedAndExplained() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var parent = root
        for _ in 0...(DAWScanner.maximumDepth + 1) { parent.appendPathComponent("nested") }
        try makeApplication(in: parent, folderName: "Fixture.app", bundleIdentifier: "test.vendor.daw", displayName: "Fixture", version: "1.0")
        let definition = DAWDefinition(id: "fixture", name: "Fixture", vendor: "Example", bundleIdentifiers: ["test.vendor.daw"], applicationNamePrefixes: [])
        let result = try DAWScanner().scanReport(configuration: .init(applicationRoots: [root], definitions: [definition]))
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.scopeNotes.count, 1)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func makeApplication(
        in root: URL,
        folderName: String,
        bundleIdentifier: String,
        displayName: String,
        version: String
    ) throws {
        let app = root.appendingPathComponent(folderName, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents,
            withIntermediateDirectories: true
        )
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleDisplayName": displayName,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "42"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
