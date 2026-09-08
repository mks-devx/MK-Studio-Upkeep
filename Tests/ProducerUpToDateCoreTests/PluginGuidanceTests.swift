// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class PluginGuidanceTests: XCTestCase {
    func testUnrecognisedSliceDoesNotBecomeIntelOnlyFindingOrMigration() {
        let p = product([bundle("au", version: "1", architectures: [.x86_64, .unknown])])
        XCTAssertTrue(PluginGuidance.intelOnlyBundles(p).isEmpty)
        XCTAssertEqual(ProductArchitectureSupportEvaluator.evaluate(product: p, catalogue: [architectureRecord()]), .notApplicable)
    }

    func testIntelSummaryDoesNotHideMixedCopies() {
        let intel = bundle("au", version: "1", architectures: [.x86_64])
        let universal = bundle("vst3", version: "1", architectures: [.arm64, .x86_64])
        XCTAssertEqual(PluginGuidance.intelCopySummary(product([intel])), "Intel-only")
        XCTAssertEqual(PluginGuidance.intelCopySummary(product([intel, universal])), "Mixed · Intel-only copies")
        XCTAssertEqual(PluginGuidance.intelCopyFormats(product([intel, universal])), "Audio Unit")
        XCTAssertNil(PluginGuidance.intelCopySummary(product([universal])))
        XCTAssertNil(PluginGuidance.intelCopySummary(product([])))
        XCTAssertNil(PluginGuidance.intelCopySummary(product([bundle("au", version: "1", architectures: [.x86_64, .unknown])])))
    }

    func testDifferentVersionsRemainVisibleForUncertainGrouping() {
        let p = product([bundle("au", version: "1.2.2"), bundle("vst3", version: "1.2.3")], uncertain: true)
        XCTAssertTrue(PluginGuidance.versionsDiffer(p))
        XCTAssertEqual(PluginUpdateEvaluator.evaluate(p, catalogue: []).updateState, .notChecked)
    }

    func testEquivalentVersionSpellingsDoNotWarn() {
        XCTAssertFalse(PluginGuidance.versionsDiffer(product([
            bundle("au", version: "1.2"), bundle("vst3", version: "1.2.0")
        ])))
    }

    func testBuildOnlyMetadataDoesNotBecomeAReleaseDifference() {
        XCTAssertFalse(PluginGuidance.versionsDiffer(product([
            bundle("au", version: nil), bundle("vst3", version: "1.2.3")
        ])))
    }

    func testIntelFindingIsPerFileEvenWhenAnotherFormatIsNative() {
        let p = product([bundle("au", version: "1", architectures: [.x86_64]),
                         bundle("vst3", version: "1", architectures: [.arm64, .x86_64])])
        XCTAssertEqual(PluginGuidance.intelOnlyBundles(p).map(\.id), ["au"])
    }

    func testContainerExplanationDoesNotAssertDifferentCommercialProducts() {
        let p = product([bundle("au", version: "1")], uncertain: true,
            evidence: [.init(reason: .multiComponentContainer, detail: "Fixture")])
        XCTAssertTrue(PluginGuidance.identityExplanation(p)?.contains("variants of one product") == true)
        XCTAssertNil(PluginGuidance.identityExplanation(product([bundle("au", version: "1")])))
    }

    func testStaleNativeEvidenceRetainsItsSourceWithoutClaimingAnUpgrade() {
        let p = product([bundle("au", version: "1")])
        let record = architectureRecord()
        let result = ProductArchitectureSupportEvaluator.evaluate(product: p, catalogue: [record],
            now: EvidenceFreshness.date("2026-09-05")!)
        XCTAssertEqual(result, .evidenceOutdated(sourceURL: record.sourceURL, checkedOn: "2026-01-01"))
    }

    func testMixedVendorBundleCannotBorrowArchitectureEvidence() {
        let p = product([bundle("au", version: "1"), bundle("vst3", version: "1", identifier: "com.other.random")])
        XCTAssertEqual(ProductArchitectureSupportEvaluator.evaluate(product: p, catalogue: [architectureRecord()]), .nativeReleaseNotConfirmed)
    }

    private func architectureRecord() -> ArchitectureSupportRecord {
        .init(vendorIdentifierPrefixes: ["com.beatsurfing."], exactProductAliases: ["RANDOM"],
            minimumNativeVersion: "1", recommendedVersion: "2", nativeFormats: [.audioUnit, .vst3],
            sourceURL: URL(string: "https://beatsurfing.com/audio-plugins/random/")!, checkedOn: "2026-01-01")
    }

    private func product(_ bundles: [PluginBundleRecord], uncertain: Bool = false,
                         evidence: [ProductMatchEvidence] = []) -> NormalizedPluginProduct {
        .init(id: "fixture", name: "RANDOM", vendor: "BEATSURFING", bundles: bundles,
              confidence: uncertain ? .low : .high, matchEvidence: evidence, requiresVerification: uncertain)
    }

    private func bundle(_ id: String, version: String?, identifier: String? = "com.BEATSURFING.PhazzRandom",
                        architectures: [BinaryArchitecture] = [.x86_64]) -> PluginBundleRecord {
        .init(id: id, name: "RANDOM", vendor: "BEATSURFING", format: id == "au" ? .audioUnit : .vst3,
              bundleIdentifier: identifier, displayVersion: version, buildVersion: "999",
              path: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/fixture/\(id)"), executablePath: nil,
              architectures: architectures, fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
    }
}
