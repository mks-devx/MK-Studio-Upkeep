// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class ProductArchitectureSupportTests: XCTestCase {
    func testNewerUnreviewedReleaseDoesNotRecommendReinstallOrDowngrade() {
        let result = ProductArchitectureSupportEvaluator.evaluate(
            product: product(version: "3.0.0"),
            catalogue: [release(minimum: "1.2.0", recommended: "1.4.0")])
        guard case .needsVerification = result else { return XCTFail("Unreviewed newer releases require verification") }
    }

    func testOlderIntelInstallRecommendsNativeUpdate() throws {
        let result = ProductArchitectureSupportEvaluator.evaluate(
            product: product(version: "1.1.0"),
            catalogue: [release(minimum: "1.2.0", recommended: "1.3.0")]
        )
        let upgrade = try nativeUpgrade(result)

        XCTAssertEqual(upgrade.action, .update)
        XCTAssertEqual(upgrade.version, "1.3.0")
        XCTAssertEqual(upgrade.formats, [.audioUnit])
    }

    func testNativeCapableVersionInstalledAsIntelRecommendsReinstall() throws {
        let result = ProductArchitectureSupportEvaluator.evaluate(
            product: product(version: "1.4.0"),
            catalogue: [release(minimum: "1.2.0", recommended: "1.4.0")]
        )

        XCTAssertEqual(try nativeUpgrade(result).action, .reinstall)
    }

    func testUniversalProductIsNotApplicable() {
        let result = ProductArchitectureSupportEvaluator.evaluate(
            product: product(version: "1.4.0", architectures: [.arm64, .x86_64]),
            catalogue: [release(minimum: "1.2.0", recommended: "1.4.0")]
        )

        XCTAssertEqual(result, .notApplicable)
    }

    func testUnknownProductDoesNotClaimNativeAvailability() {
        let result = ProductArchitectureSupportEvaluator.evaluate(
            product: product(version: "1.0.0"),
            catalogue: []
        )

        XCTAssertEqual(result, .nativeReleaseNotConfirmed)
    }

    func testUnsupportedInstalledFormatDoesNotClaimAvailability() {
        let result = ProductArchitectureSupportEvaluator.evaluate(
            product: product(version: "1.0.0", format: .vst2),
            catalogue: [release(minimum: "1.2.0", recommended: "1.4.0")]
        )

        XCTAssertEqual(result, .nativeReleaseNotConfirmed)
    }

    private func nativeUpgrade(
        _ result: ProductArchitectureCheckResult
    ) throws -> ProductArchitectureUpgrade {
        guard case let .nativeReleaseAvailable(upgrade) = result else {
            XCTFail("Expected a native release, got \(result)")
            throw NSError(domain: "test", code: 1)
        }
        return upgrade
    }

    private func product(
        version: String,
        format: PluginFormat = .audioUnit,
        architectures: [BinaryArchitecture] = [.x86_64]
    ) -> NormalizedPluginProduct {
        let bundle = PluginBundleRecord(
            id: "bundle",
            name: "Fixture",
            vendor: "Kush Audio",
            format: format,
            bundleIdentifier: "com.kush.fixture",
            displayVersion: version,
            buildVersion: nil,
            path: URL(fileURLWithPath: "/Library/Fixture.component"),
            executablePath: nil,
            architectures: architectures,
            fileSize: nil,
            modifiedAt: nil,
            evidence: [],
            issues: []
        )
        return NormalizedPluginProduct(
            id: "product",
            name: "Fixture",
            vendor: "Kush Audio",
            bundles: [bundle],
            confidence: .high,
            matchEvidence: [],
            requiresVerification: false
        )
    }

    private func release(
        minimum: String,
        recommended: String
    ) -> ArchitectureSupportRecord {
        ArchitectureSupportRecord(
            vendorIdentifierPrefixes: ["com.kush."],
            exactProductAliases: ["Fixture"],
            minimumNativeVersion: minimum,
            recommendedVersion: recommended,
            nativeFormats: [.audioUnit],
            sourceURL: URL(string: "https://vendor.example/native")!,
            checkedOn: EvidenceFreshness.day(Date())
        )
    }
}
