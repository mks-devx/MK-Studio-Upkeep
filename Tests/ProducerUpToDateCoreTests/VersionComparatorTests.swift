// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class VersionComparatorTests: XCTestCase {
    func testAbletonDatedHashSuffix() {
        XCTAssertEqual(VersionComparator.releaseValue("12.4.5 (2026-08-19_0123456789)"), "12.4.5")
        XCTAssertNil(VersionComparator.releaseValue("12.4.5 (unverified suffix)"))
        XCTAssertNil(VersionComparator.releaseValue("12.4.5beta1 (2026-08-19_0123456789)"))
    }

    func testLeadingVAndMissingComponentsCompareEqual() {
        XCTAssertEqual(
            VersionComparator.compare("v3.2", "3.2.0"),
            .equal
        )
    }

    func testNumericComparisonIsNotLexicographic() {
        XCTAssertEqual(
            VersionComparator.compare("2.9.0", "2.10.0"),
            .older
        )
    }

    func testPrereleaseChannelsSortBeforeStable() {
        XCTAssertEqual(
            VersionComparator.compare("1.5.0b3", "1.5.0"),
            .older
        )
        XCTAssertEqual(
            VersionComparator.compare("1.5.0rc2", "1.5.0b9"),
            .newer
        )
    }

    func testFourthComponentIsPreserved() {
        XCTAssertEqual(
            VersionComparator.compare("15.0.0.122", "15.0.0.123"),
            .older
        )
    }

    func testUnknownMarketingVersionIsIncomparable() {
        XCTAssertEqual(
            VersionComparator.compare("Summer 2026", "3.0"),
            .incomparable
        )
    }
}
