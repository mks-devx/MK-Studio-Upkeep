// SPDX-License-Identifier: BUSL-1.1
import Foundation
import XCTest
@testable import ProducerUpToDateCore

final class ProductNormalizerTests: XCTestCase {
    func testReusedVendorIdentifierDoesNotCollideAcrossSeparateProducts() {
        let records: [PluginBundleRecord] = [("one", "Compressor", "Example"), ("two", "Limiter", "Example"), ("three", "Compressor", "Other")].flatMap { entry -> [PluginBundleRecord] in
            let (id, name, vendor) = entry
            return [PluginFormat.audioUnit, .vst3].map { format in
                record(id: id + format.rawValue, name: name, vendor: vendor, format: format, version: "1",
                       bundleIdentifier: "com.example.shared", identifiers: [.init(kind: .bundleIdentifier, value: "com.example.shared")])
            }
        }
        let products = ProductNormalizer().normalize(records: records).products
        XCTAssertEqual(products.count, 3)
        XCTAssertEqual(Set(products.map(\.id)).count, 3)
        XCTAssertEqual(products.map(\.id), ProductNormalizer().normalize(records: records.reversed()).products.map(\.id))
    }

    func testAddingAFormatPreservesProductIdentityAndScanHistory() {
        let identifier = "com.example.fixture"
        let first = record(id: "au", name: "Fixture", vendor: "Example", format: .audioUnit, version: "1.0",
            bundleIdentifier: identifier, identifiers: [.init(kind: .bundleIdentifier, value: identifier)])
        let second = record(id: "vst", name: "Fixture", vendor: "Example", format: .vst3, version: "1.0",
            bundleIdentifier: identifier, identifiers: [.init(kind: .bundleIdentifier, value: identifier)])
        let before = ProductNormalizer().normalize(records: [first]).products
        let after = ProductNormalizer().normalize(records: [first, second]).products
        XCTAssertEqual(before.first?.id, after.first?.id)
        let comparison = ScanComparison(previous: .init(finishedAt: Date(), products: before, scopeID: "fixture"),
            current: .init(finishedAt: Date(), products: after, scopeID: "fixture"))
        XCTAssertTrue(comparison.added.isEmpty)
        XCTAssertTrue(comparison.removed.isEmpty)
    }

    func testDifferentInstalledEditionsStaySeparateWhenFormatsChange() {
        let identifier = "com.example.fixture"
        func edition(_ major: Int, _ format: PluginFormat) -> PluginBundleRecord {
            record(id: "fixture-\(major)-\(format.rawValue)", name: "Fixture \(major)", vendor: "Example", format: format,
                version: "\(major).0", bundleIdentifier: identifier,
                identifiers: [.init(kind: .bundleIdentifier, value: identifier)])
        }
        let before = ProductNormalizer().normalize(records: [edition(1, .audioUnit), edition(2, .audioUnit)]).products
        let after = ProductNormalizer().normalize(records: [edition(1, .audioUnit), edition(2, .audioUnit), edition(2, .vst3)]).products
        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(Set(after.map(\.id)).count, 2)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: before.map { ($0.name, $0.id) }),
            Dictionary(uniqueKeysWithValues: after.map { ($0.name, $0.id) }))
        XCTAssertEqual(after.first { $0.name == "Fixture 1" }?.bundles.count, 1)
        XCTAssertEqual(after.first { $0.name == "Fixture 2" }?.bundles.count, 2)
    }

    func testTokyoDawnVendorSpellingsGroupFormatsOnce() {
        let products = ProductNormalizer().normalize(records: [
            record(id: "au", name: "TDR Nova", vendor: "TokyoDawnLabs", format: .audioUnit, version: "2.2.1"),
            record(id: "vst3", name: "TDR Nova", vendor: "Tokyo Dawn Labs", format: .vst3, version: "2.2.1")
        ]).products
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.bundles.count, 2)
        XCTAssertEqual(products.first?.vendor, "Tokyo Dawn Labs")
    }

    func testGroupsFormatsByCanonicalVendorAndProductName() {
        let report = ProductNormalizer().normalize(
            records: [
                record(
                    id: "au",
                    name: "Pro-Q 3",
                    vendor: "FabFilter",
                    format: .audioUnit,
                    version: "3.26"
                ),
                record(
                    id: "vst3",
                    name: "Pro-Q 3",
                    vendor: "FabFilter Software",
                    format: .vst3,
                    version: "3.26"
                )
            ]
        )

        XCTAssertEqual(report.products.count, 1)
        XCTAssertEqual(report.products[0].bundles.count, 2)
        XCTAssertEqual(report.products[0].formats, [.audioUnit, .vst3])
        XCTAssertEqual(report.products[0].confidence, .medium)
        XCTAssertFalse(report.products[0].requiresVerification)
    }

    func testCanonicalizesNativeInstrumentsAliases() {
        let report = ProductNormalizer().normalize(
            records: [
                record(
                    id: "au",
                    name: "Massive X",
                    vendor: "Native Instruments GmbH",
                    format: .audioUnit,
                    version: "1.5.1"
                ),
                record(
                    id: "vst3",
                    name: "Massive X",
                    vendor: "native-instruments",
                    format: .vst3,
                    version: "1.5.1"
                )
            ]
        )

        XCTAssertEqual(report.products.count, 1)
        XCTAssertEqual(report.products[0].vendor, "Native Instruments")
    }

    func testInfersMissingVendorOnlyForOneCompatibleProduct() {
        let report = ProductNormalizer().normalize(
            records: [
                record(
                    id: "au",
                    name: "Super 8",
                    vendor: "Native Instruments",
                    format: .audioUnit,
                    version: "2.1.0",
                    bundleIdentifier: "Super 8.MusicDevice.component"
                ),
                record(
                    id: "vst3",
                    name: "Super 8",
                    vendor: nil,
                    format: .vst3,
                    version: "2.1.0",
                    bundleIdentifier: "Super 8.vst3"
                )
            ]
        )

        XCTAssertEqual(report.products.count, 1)
        XCTAssertEqual(report.products[0].bundles.count, 2)
        XCTAssertEqual(report.products[0].confidence, .low)
        XCTAssertTrue(report.products[0].requiresVerification)
        XCTAssertTrue(
            report.products[0].matchEvidence.contains {
                $0.reason == .missingVendorInferred
            }
        )
    }

    func testDoesNotMergeSameNameAcrossVendors() {
        let report = ProductNormalizer().normalize(
            records: [
                record(
                    id: "one",
                    name: "Compressor",
                    vendor: "Vendor One",
                    format: .audioUnit,
                    version: "1.0.0"
                ),
                record(
                    id: "two",
                    name: "Compressor",
                    vendor: "Vendor Two",
                    format: .vst3,
                    version: "1.0.0"
                )
            ]
        )

        XCTAssertEqual(report.products.count, 2)
    }

    func testMarksMultiComponentContainerForVerification() {
        let report = ProductNormalizer().normalize(
            records: [
                record(
                    id: "shell",
                    name: "Vendor Shell",
                    vendor: "Example",
                    format: .vst3,
                    version: "4.0.0",
                    identifiers: [
                        PluginIdentifier(kind: .vst3Class, value: "class-one"),
                        PluginIdentifier(kind: .vst3Class, value: "class-two")
                    ]
                )
            ]
        )

        XCTAssertEqual(report.products[0].confidence, .low)
        XCTAssertTrue(report.products[0].requiresVerification)
        XCTAssertTrue(
            report.products[0].matchEvidence.contains {
                $0.reason == .multiComponentContainer
            }
        )
    }

    func testStableProductIDDoesNotDependOnInputOrderOrPath() {
        let first = ProductNormalizer().normalize(
            records: [
                record(
                    id: "one",
                    name: "Example",
                    vendor: "Example Audio",
                    format: .audioUnit,
                    version: "1.0.0",
                    path: "/Library/Audio/Plug-Ins/Components/Example.component"
                ),
                record(
                    id: "two",
                    name: "Example",
                    vendor: "Example Audio",
                    format: .vst3,
                    version: "1.0.0",
                    path: "/Library/Audio/Plug-Ins/VST3/Example.vst3"
                )
            ]
        )
        let second = ProductNormalizer().normalize(
            records: [
                record(
                    id: "changed-two",
                    name: "Example",
                    vendor: "Example Audio",
                    format: .vst3,
                    version: "1.0.0",
                    path: "/Custom/VST3/Example.vst3"
                ),
                record(
                    id: "changed-one",
                    name: "Example",
                    vendor: "Example Audio",
                    format: .audioUnit,
                    version: "1.0.0",
                    path: "/Custom/AU/Example.component"
                )
            ]
        )

        XCTAssertEqual(first.products[0].id, second.products[0].id)
    }

    func testPreservesVersionDivergenceWithinProduct() {
        let report = ProductNormalizer().normalize(
            records: [
                record(
                    id: "au",
                    name: "Example",
                    vendor: "Example Audio",
                    format: .audioUnit,
                    version: "1.0.0"
                ),
                record(
                    id: "vst3",
                    name: "Example",
                    vendor: "Example Audio",
                    format: .vst3,
                    version: "1.1.0"
                )
            ]
        )

        XCTAssertEqual(report.products.count, 1)
        XCTAssertTrue(report.products[0].hasVersionDivergence)
        XCTAssertEqual(report.products[0].installedVersions, ["1.0.0", "1.1.0"])
    }

    private func record(
        id: String,
        name: String,
        vendor: String?,
        format: PluginFormat,
        version: String?,
        bundleIdentifier: String? = nil,
        identifiers: [PluginIdentifier] = [],
        path: String? = nil
    ) -> PluginBundleRecord {
        PluginBundleRecord(
            id: id,
            name: name,
            vendor: vendor,
            format: format,
            bundleIdentifier: bundleIdentifier,
            displayVersion: version,
            buildVersion: nil,
            path: URL(
                fileURLWithPath: path
                    ?? "/tmp/\(id).\(format.pathExtension)"
            ),
            executablePath: nil,
            architectures: [.arm64],
            fileSize: nil,
            modifiedAt: nil,
            identifiers: identifiers,
            evidence: [],
            issues: []
        )
    }
}
