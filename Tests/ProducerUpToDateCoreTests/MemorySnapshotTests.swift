// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class MemorySnapshotTests: XCTestCase {
    func testSubtractsReclaimablePagesAndIncludesCompressor() {
        XCTAssertEqual(MemorySnapshot.estimatedUsed(total: 10000, pageSize: 10, active: 100,
            inactive: 50, wired: 20, compressor: 10, purgeable: 5, external: 25), 1500)
    }
    func testInconsistentAndOverflowingReadingsAreUnavailable() {
        XCTAssertNil(MemorySnapshot.estimatedUsed(total: 100, pageSize: 1, active: 1,
            inactive: 0, wired: 0, compressor: 0, purgeable: 2, external: 0))
        XCTAssertNil(MemorySnapshot.estimatedUsed(total: 100, pageSize: 1, active: .max,
            inactive: 1, wired: 0, compressor: 0, purgeable: 0, external: 0))
    }
}
