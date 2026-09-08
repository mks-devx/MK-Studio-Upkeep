// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class LocalProductReviewTests: XCTestCase {
    func product(_ name: String, version: String = "2.0", architecture: [BinaryArchitecture] = [.arm64], vendor: String = "Example", format: PluginFormat = .audioUnit, path: String = "/fixtures/a.component") -> NormalizedPluginProduct {
        let bundle = PluginBundleRecord(id: path, name: name, vendor: vendor, format: format, bundleIdentifier: "com.example." + name,
            displayVersion: version, buildVersion: "900", path: URL(fileURLWithPath: path), executablePath: nil,
            architectures: architecture, fileSize: nil, modifiedAt: nil, evidence: [], issues: [])
        return .init(id: name, name: name, vendor: vendor, bundles: [bundle], confidence: .high, matchEvidence: [], requiresVerification: false)
    }
    func testOldDateAndIntelDoNotMeanBroken() {
        XCTAssertFalse(LocalProductReview.cannotRun(product("Fixture", architecture: [.x86_64]), processor: .appleSilicon))
        XCTAssertTrue(LocalProductReview.cannotRun(product("Fixture", architecture: [.i386]), processor: .appleSilicon))
        XCTAssertTrue(LocalProductReview.cannotRun(product("Fixture"), processor: .intel))
        XCTAssertFalse(LocalProductReview.cannotRun(product("Fixture", architecture: []), processor: .appleSilicon))
    }
    func testFormatsAreNotDuplicateCopies() {
        let first = product("Fixture")
        let second = product("Fixture", format: .vst3, path: "/fixtures/a.vst3")
        let both = NormalizedPluginProduct(id: "p", name: "Fixture", vendor: "Example", bundles: first.bundles + second.bundles, confidence: .high, matchEvidence: [], requiresVerification: false)
        XCTAssertFalse(LocalProductReview.hasRepeatedFormat(both))
        let repeated = product("Fixture", path: "/fixtures/other.component")
        let copies = NormalizedPluginProduct(id: "p", name: "Fixture", vendor: "Example", bundles: first.bundles + repeated.bundles, confidence: .high, matchEvidence: [], requiresVerification: false)
        XCTAssertTrue(LocalProductReview.hasRepeatedFormat(copies))
    }
    func testRelatedEditionsRequireVendorAndMatchingMajor() {
        let old = product("FixtureBox 2"), new = product("FixtureBox", version: "3.0")
        let index = LocalProductReview.relatedEditions([old, new])
        XCTAssertEqual(index[old.id]?.map(\.id), [new.id])
        XCTAssertNil(LocalProductReview.relatedEditions([old, product("FixtureBox", version: "3.0", vendor: "Other")])[old.id])
        XCTAssertNil(LocalProductReview.relatedEditions([product("FixtureBox 2", version: "9.0"), new])[old.id])
    }
    func testFriendlyNamePreservesTechnicalNamesExceptSeparators() {
        XCTAssertEqual(LocalProductReview.displayName("AFX2DAW_MONO"), "AFX2DAW MONO")
        XCTAssertEqual(LocalProductReview.displayName("Pro-Q 3"), "Pro-Q 3")
    }
}
