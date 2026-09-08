// SPDX-License-Identifier: MPL-2.0
import XCTest
import Darwin
@testable import ProducerUpToDateCore

final class BundleProvenanceTests: XCTestCase {
    func testRejectedMetadataNeverOpensItsDeclaredFIFOExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for placement in ["inside", "outside", "oversized", "missing", "malformed", "empty"] {
            let bundle = root.appendingPathComponent(placement + ".driver")
            let usesFallback = ["missing", "malformed", "empty"].contains(placement)
            let executable = bundle.appendingPathComponent("Contents/MacOS/" + (usesFallback ? placement : "Fixture"))
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            XCTAssertEqual(mkfifo(executable.path, 0o600), 0)
            var plist: [String: Any] = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "com.example.fixture",
                                      "padding": placement == "oversized" ? String(repeating: "x", count: 4_194_304) : ""]
            if placement == "missing" { plist.removeValue(forKey: "CFBundleExecutable") }
            if placement == "malformed" { plist["CFBundleExecutable"] = false }
            if placement == "empty" { plist["CFBundleExecutable"] = "" }
            let info = bundle.appendingPathComponent("Contents/Info.plist")
            let target = placement == "inside" ? bundle.appendingPathComponent("Contents/metadata.plist")
                : placement == "outside" ? root.appendingPathComponent("metadata.plist") : info
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: target)
            if target != info { try FileManager.default.createSymbolicLink(at: info, withDestinationURL: target) }
            let refused = BundleProvenance.executableIsUnsafeToOpen(at: bundle)
            XCTAssertTrue(refused, "Rejected \(placement) metadata must never be handed to Security")
            // Keep a regression bounded: the old implementation blocks in Security after
            // returning false here. A failed preflight assertion must not hang the test runner.
            if refused {
                let start = Date()
                XCTAssertEqual(BundleProvenance.read(at: bundle).signature, .notVerified)
                XCTAssertLessThan(Date().timeIntervalSince(start), 2)
            }
        }
    }

    func testValidAdHocSignatureHasNoVerifiedIdentityAndTamperingIsInvalid() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for architecture in ["arm64", "x86_64"] {
            let bundle = root.appendingPathComponent(architecture + ".driver")
            let executable = bundle.appendingPathComponent("Contents/MacOS/Fixture")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            let source = root.appendingPathComponent("fixture.c")
            let marker = "fixture-signature-payload-0123456789"
            let program = "const char fixture_marker[] = \"\(marker)\"; int main(void) { return fixture_marker[0]; }\n"
            try Data(program.utf8).write(to: source)
            try runFixtureCommand("/usr/bin/clang", ["-arch", architecture, source.path, "-o", executable.path])
            let plist = ["CFBundleExecutable": "Fixture", "CFBundleIdentifier": "com.example.fixture", "CFBundlePackageType": "BNDL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            try runFixtureCommand("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", "com.example.fixture", bundle.path])
            let provenance = BundleProvenance.read(at: bundle)
            XCTAssertEqual(provenance.signature, .adHoc)
            XCTAssertNil(provenance.signer)
            XCTAssertNil(provenance.teamIdentifier)
            XCTAssertEqual(provenance.summary, "Signed without an identity")
            let resources = bundle.appendingPathComponent("Contents/_CodeSignature/CodeResources")
            let originalResources = try Data(contentsOf: resources)
            try FileManager.default.removeItem(at: resources)
            XCTAssertEqual(mkfifo(resources.path, 0o600), 0)
            let refused = BundleProvenance.executableIsUnsafeToOpen(at: bundle)
            XCTAssertTrue(refused, "Security must never open signature-resource metadata that is a FIFO")
            if refused { XCTAssertEqual(BundleProvenance.read(at: bundle).signature, .notVerified) }
            try FileManager.default.removeItem(at: resources)
            try originalResources.write(to: resources)
            var bytes = try Data(contentsOf: executable)
            // Mutate actual signed payload: fixed offsets can land in unsigned signature
            // allocation padding, whose position differs between Intel and Apple Silicon.
            let payload = try XCTUnwrap(bytes.range(of: Data(marker.utf8)))
            bytes[payload.lowerBound] ^= 1
            try bytes.write(to: executable)
            XCTAssertEqual(BundleProvenance.read(at: bundle).signature, .invalid)
        }
    }

    private func runFixtureCommand(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        guard ended.wait(timeout: .now() + 20) == .success else {
            process.terminate()
            if ended.wait(timeout: .now() + 1) != .success { kill(process.processIdentifier, SIGKILL) }
            XCTFail("Synthetic fixture command exceeded its time limit")
            throw CocoaError(.executableRuntimeMismatch)
        }
        XCTAssertEqual(process.terminationStatus, 0, "Synthetic fixture command failed")
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
    }

    func testCertificateSummariesAreClassifiedAndOrganisationExtracted() {
        XCTAssertEqual(BundleProvenance.organisation(from: "Developer ID Application: Example Audio Ltd (ABCDEFGH12)"), "Example Audio Ltd")
        XCTAssertEqual(BundleProvenance.organisation(from: "Developer ID Application: Example Developer (ABCDEFGH12)"), "Example Developer")
        XCTAssertEqual(BundleProvenance.organisation(from: "Apple Distribution: Example GmbH (ABCDEFGH12)"), "Example GmbH")
        XCTAssertEqual(BundleProvenance.organisation(from: "Software Signing"), "Software Signing")
        XCTAssertNil(BundleProvenance.organisation(from: "Developer ID Application:  (ABCDEFGH12)"))
        XCTAssertEqual(BundleProvenance.classify("Software Signing"), .apple)
        XCTAssertEqual(BundleProvenance.classify("Developer ID Application: X (ABCDEFGH12)"), .developerID)
        XCTAssertEqual(BundleProvenance.classify("Apple Distribution: X (ABCDEFGH12)"), .macAppStore)
        XCTAssertEqual(BundleProvenance.classify("Apple Mac OS Application Signing"), .macAppStore, "Store-signed third-party software is not Apple's own")
        XCTAssertEqual(BundleProvenance.classify("Some Self-Signed Thing"), .adHoc)
    }

    func testReadsAppleSignatureOfASystemAppAndUnsignedFixture() throws {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let provenance = BundleProvenance.read(at: finder)
        XCTAssertEqual(provenance.signature, .apple)
        XCTAssertTrue(provenance.summary.hasPrefix("Signed by Apple"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Fixture.driver/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fixture", "NSHumanReadableCopyright": "© 2026 Example Audio"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
        let unsigned = BundleProvenance.read(at: bundle.deletingLastPathComponent())
        XCTAssertEqual(unsigned.signature, .unsigned)
        XCTAssertEqual(unsigned.copyright, "© 2026 Example Audio")
        XCTAssertEqual(unsigned.summary, "Not signed · © 2026 Example Audio")
    }

    func testDescriptionsUseProvenanceWhenNoGuideExists() {
        func driver(_ p: BundleProvenance?) -> DriverRecord {
            DriverRecord(path: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/HAL/X.driver"), name: "X", bundleIdentifier: "com.unknownmaker.x", version: "1.0", kind: "Core Audio driver", provenance: p)
        }
        let signed = driver(BundleProvenance(signature: .developerID, signer: "Unknown Maker Ltd", teamIdentifier: "ABCDEFGH12", copyright: "© 2025 Unknown Maker Ltd"))
        XCTAssertTrue(DriverDescription.describe(signed).contains("Signed by Unknown Maker Ltd"))
        XCTAssertEqual(DriverDescription.maker(of: signed), "Unknown Maker Ltd")
        let apple = driver(BundleProvenance(signature: .apple, signer: "Software Signing", teamIdentifier: nil, copyright: "Copyright © 2022 Apple Inc."))
        XCTAssertTrue(DriverDescription.describe(apple).contains("Signed by Apple"))
        XCTAssertEqual(DriverDescription.maker(of: apple), "Apple")
        let unsigned = driver(BundleProvenance(signature: .unsigned, signer: nil, teamIdentifier: nil, copyright: "© Someone"))
        XCTAssertTrue(DriverDescription.describe(unsigned).contains("not signed with a verified identity"))
        XCTAssertEqual(DriverDescription.maker(of: driver(nil)), "Maker “unknownmaker”")
        let report = DriverDescription.maintainerReport(for: signed)
        XCTAssertTrue(report.contains("com.unknownmaker.x") && report.contains("Unknown Maker Ltd") && report.contains("team ABCDEFGH12"))
        XCTAssertFalse(report.contains(NSUserName()))
    }
}
