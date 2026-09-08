// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class ArchitectureUpgradeEvaluatorTests: XCTestCase {
    func testBuildNumberIsNotComparedWithVendorReleaseVersion() {
        let result = ArchitectureUpgradeEvaluator.evaluate(
            installed: record(version: nil, architectures: [.x86_64], buildVersion: "2000"),
            release: release(version: "2000", formats: [.vst3]))
        guard case let .nativeReleaseAvailable(_, action, _) = result else { return XCTFail("Expected manual version review") }
        XCTAssertEqual(action, .reviewVersions)
    }

    func testNewerNativeReleaseRecommendsUpdate() throws {
        let result = ArchitectureUpgradeEvaluator.evaluate(
            installed: record(version: "1.4.0", architectures: [.x86_64]),
            release: release(version: "2.0.0", formats: [.vst3])
        )

        XCTAssertEqual(
            result,
            .nativeReleaseAvailable(
                version: "2.0.0",
                action: .update,
                officialURL: try XCTUnwrap(URL(string: "https://example.com/download"))
            )
        )
    }

    func testSameNativeReleaseRecommendsReinstall() throws {
        let result = ArchitectureUpgradeEvaluator.evaluate(
            installed: record(version: "2.0.0", architectures: [.x86_64]),
            release: release(version: "2.0.0", formats: [.vst3])
        )

        XCTAssertEqual(
            result,
            .nativeReleaseAvailable(
                version: "2.0.0",
                action: .reinstall,
                officialURL: try XCTUnwrap(URL(string: "https://example.com/download"))
            )
        )
    }

    func testNativeReleaseForAnotherFormatIsNotClaimed() {
        let result = ArchitectureUpgradeEvaluator.evaluate(
            installed: record(version: "1.0.0", architectures: [.x86_64]),
            release: release(version: "2.0.0", formats: [.audioUnit])
        )

        XCTAssertEqual(result, .nativeReleaseNotConfirmed)
    }

    func testStaleEvidenceNeedsVerification() {
        let result = ArchitectureUpgradeEvaluator.evaluate(
            installed: record(version: "1.0.0", architectures: [.x86_64]),
            release: release(
                version: "2.0.0",
                formats: [.vst3],
                isFresh: false
            )
        )

        XCTAssertEqual(
            result,
            .needsVerification(
                reason: "The Apple Silicon release evidence needs refreshing."
            )
        )
    }

    func testUniversalInstalledBundleNeedsNoMigration() {
        let result = ArchitectureUpgradeEvaluator.evaluate(
            installed: record(
                version: "2.0.0",
                architectures: [.arm64, .x86_64]
            ),
            release: release(version: "2.0.0", formats: [.vst3])
        )

        XCTAssertEqual(result, .notApplicable)
    }

    private func record(
        version: String?,
        architectures: [BinaryArchitecture],
        buildVersion: String? = nil
    ) -> PluginBundleRecord {
        PluginBundleRecord(
            id: "fixture",
            name: "Fixture",
            vendor: "Example",
            format: .vst3,
            bundleIdentifier: "com.example.fixture",
            displayVersion: version,
            buildVersion: buildVersion,
            path: URL(fileURLWithPath: "/tmp/Fixture.vst3"),
            executablePath: URL(fileURLWithPath: "/tmp/Fixture"),
            architectures: architectures,
            fileSize: nil,
            modifiedAt: nil,
            evidence: [],
            issues: []
        )
    }

    private func release(
        version: String,
        formats: Set<PluginFormat>,
        isFresh: Bool = true
    ) -> CatalogueRelease {
        CatalogueRelease(
            productID: "example.fixture",
            displayVersion: version,
            formats: formats,
            architectures: [.arm64, .x86_64],
            officialURL: URL(string: "https://example.com/download")!,
            confidence: .high,
            verifiedAt: Date(),
            isFresh: isFresh
        )
    }
}
