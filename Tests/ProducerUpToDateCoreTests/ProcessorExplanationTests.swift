// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class ProcessorExplanationTests: XCTestCase {
    func testIntelIsNotTreatedAsMigrationProblemOnIntelMac() {
        XCTAssertTrue(InstalledArchitecture.intel64.explanation(on: .intel).contains("do not need an Apple Silicon"))
        XCTAssertTrue(InstalledArchitecture.intel64.explanation(on: .appleSilicon).contains("Rosetta"))
    }
    func testSiliconOnlyCannotBeRecommendedForIntel() {
        XCTAssertTrue(InstalledArchitecture.appleSilicon.explanation(on: .intel).contains("cannot run on an Intel Mac"))
    }
    func testUnknownAndUniversalDoNotCertifyCompatibility() {
        XCTAssertTrue(InstalledArchitecture.unknown.explanation(on: .appleSilicon).contains("not proof of incompatibility"))
        XCTAssertTrue(InstalledArchitecture.universal.explanation(on: .appleSilicon).contains("still need to be supported"))
        XCTAssertTrue(InstalledArchitecture.intel64.explanation(on: .unknown).contains("could not be confirmed"))
    }
    func testRosettaDoesNotRescue32Bit() {
        XCTAssertTrue(InstalledArchitecture.legacy32.explanation(on: .appleSilicon).contains("does not restore"))
    }
}
