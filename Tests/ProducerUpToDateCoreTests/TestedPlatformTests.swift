// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class TestedPlatformTests: XCTestCase {
    func testRemovalAvailableAcrossSupportedVersionsAndArchitectures() {
        for native in [true, false] {
            for major in [13, 14, 15, 26, 27] {
                XCTAssertTrue(TestedPlatform.permitsRemoval(isNativeAppleSilicon: native,
                    version: OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)))
            }
            XCTAssertFalse(TestedPlatform.permitsRemoval(isNativeAppleSilicon: native,
                version: OperatingSystemVersion(majorVersion: 12, minorVersion: 7, patchVersion: 0)))
        }
    }

    func testAvailabilityDoesNotExpandClaimsOfTestCoverage() {
        let tested = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 2)
        XCTAssertTrue(TestedPlatform.isTested(isNativeAppleSilicon: true, version: tested))
        XCTAssertFalse(TestedPlatform.isTested(isNativeAppleSilicon: false, version: tested))
        for version in [OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0),
                        OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1),
                        OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 3),
                        OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)] {
            XCTAssertFalse(TestedPlatform.isTested(isNativeAppleSilicon: true, version: version))
        }
    }
}
