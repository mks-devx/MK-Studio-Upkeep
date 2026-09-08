// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class ProcessActivityTests: XCTestCase {
    func testRanksMulticoreReadingsPreservesNamesAndExcludesSampler() {
        let result = ProcessActivity.parse("1 2.0 100 Audio Host\n2 180.2 50 Render Worker\n3 99 10 ps\n4 0 5 Idle", excluding: 3)
        XCTAssertEqual(result.map(\.id), [2, 1, 4])
        XCTAssertEqual(result[1].name, "Audio Host")
        XCTAssertEqual(result[0].cpu, 180.2)
    }
    func testRejectsMalformedValuesAndBoundsResults() {
        let rows = "0 1 invalid\n8 nan Bad\n9 inf Bad\n10 -1 Bad\nbroken\n" + (1...7).map { "\($0) 2 10 Fixture" }.joined(separator: "\n")
        XCTAssertEqual(ProcessActivity.parse(rows).map(\.id), [1, 2, 3, 4, 5])
    }
    func testSanitisesUntrustedProcessNames() {
        XCTAssertEqual(ProcessActivity.parse("1 1 10 Fi\u{202e}xture").first?.name, "Fixture")
    }
    func testMemoryRankingIsIndependentAndConvertsKiB() {
        let rows = "1 99 10 CPU Worker\n2 1 4096 Memory Worker\n3 0 4096 Another Worker"
        let result = ProcessActivity.parse(rows, ranking: .memory)
        XCTAssertEqual(result.map(\.id), [2, 3, 1])
        XCTAssertEqual(result[0].residentBytes, 4_194_304)
        XCTAssertEqual(ProcessActivity.parse(rows).first?.id, 1)
    }
    func testRejectsNegativeAndOverflowingMemory() {
        XCTAssertTrue(ProcessActivity.parse("1 2 -1 Invalid\n2 3 18446744073709551615 Huge", ranking: .memory).isEmpty)
    }

}
