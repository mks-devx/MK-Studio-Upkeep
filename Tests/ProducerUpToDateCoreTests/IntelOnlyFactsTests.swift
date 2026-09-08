// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class IntelOnlyFactsTests: XCTestCase {
    func testRosettaDetectionNeverGuesses() {
        XCTAssertEqual(RosettaStatus.detect(processor: .intel, fileExists: { _ in false }), .notNeeded)
        XCTAssertEqual(RosettaStatus.detect(processor: .unknown, fileExists: { _ in true }), .unknown)
        XCTAssertEqual(RosettaStatus.detect(processor: .appleSilicon, fileExists: { _ in false }), .missing)
        XCTAssertEqual(RosettaStatus.detect(processor: .appleSilicon, fileExists: { $0.hasSuffix("/rosetta") }), .installed)
        XCTAssertTrue(RosettaStatus.missing.sentence.contains("cannot load"))
        XCTAssertTrue(RosettaStatus.installed.sentence.contains("not a promise"))
    }

    func testHostIsPreselectedOnlyWhenUnambiguous() {
        XCTAssertEqual(GuidanceHost.detected(installedDefinitionIDs: ["logic-pro"]), .logic)
        XCTAssertEqual(GuidanceHost.detected(installedDefinitionIDs: ["ableton-live", "reaper"]), .live)
        XCTAssertEqual(GuidanceHost.detected(installedDefinitionIDs: ["logic-pro", "ableton-live"]), .unspecified)
        XCTAssertEqual(GuidanceHost.detected(installedDefinitionIDs: ["bitwig-studio"]), .other)
        XCTAssertEqual(GuidanceHost.detected(installedDefinitionIDs: []), .unspecified)
    }

    func testFactsStateEvidenceNotStability() {
        let bundle = PluginBundleRecord(id: "fixture-au", name: "Fixture", vendor: "Example", format: .audioUnit, bundleIdentifier: "com.example.fixture",
                                        displayVersion: "1.0", buildVersion: nil, path: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components/Fixture.component"),
                                        executablePath: nil, architectures: [.x86_64], fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        let product = NormalizedPluginProduct(id: "fixture", name: "Fixture", vendor: "Example", bundles: [bundle],
                                              confidence: .high, matchEvidence: [], requiresVerification: false)
        let facts = IntelOnlyFacts(product: product, nativeCheck: .nativeReleaseNotConfirmed, rosetta: .missing)
        XCTAssertTrue(facts.files.hasPrefix("Intel-only files: Audio Unit"))
        XCTAssertTrue(facts.nativeVersion.contains("not on record"))
        XCTAssertTrue(facts.rosetta.contains("cannot load"))
        for text in [facts.files, facts.nativeVersion, facts.rosetta] {
            XCTAssertFalse(text.lowercased().contains("stable"), "Facts never claim stability: \(text)")
        }
    }
}
