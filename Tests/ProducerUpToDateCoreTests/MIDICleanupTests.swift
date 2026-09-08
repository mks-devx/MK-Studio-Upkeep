// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class MIDICleanupTests: XCTestCase {
    private func device(_ name: String, maker: String = "Vendor", offline: Bool?, id: UInt32 = 4_000_000_000) -> MIDIHardwareRecord {
        MIDIHardwareRecord(id: id, name: name, manufacturer: maker, offline: offline)
    }
    func testOnlyDisconnectedThirdPartyEntriesAreRemovable() {
        XCTAssertTrue(MIDICleanup.isRemovable(device("Fixture Pad Controller", maker: "Akai", offline: true)))
        XCTAssertFalse(MIDICleanup.isRemovable(device("Fixture Controller", maker: "Ableton", offline: false)))
        XCTAssertFalse(MIDICleanup.isRemovable(device("Mystery", offline: nil)), "Unknown connection state is treated as connected")
        XCTAssertFalse(MIDICleanup.isRemovable(device("IAC Driver", maker: "Apple Inc.", offline: true)))
        XCTAssertFalse(MIDICleanup.isRemovable(device("Network", maker: "", offline: false)))
        XCTAssertTrue(MIDICleanup.protection(device("Fixture Controller", maker: "Ableton", offline: false)).isRed)
        XCTAssertTrue(MIDICleanup.protection(device("IAC Driver", maker: "Apple Inc.", offline: true)).isRed)
        XCTAssertEqual(MIDICleanup.protection(device("Fixture Pad Controller", maker: "Akai", offline: true)).headline, "Read before removing")
    }
    func testRemovalRefusesProtectedAndVanishedEntriesWithoutTouchingTheSetup() {
        XCTAssertThrowsError(try MIDICleanup.remove(device("Fixture Controller", maker: "Ableton", offline: false))) { XCTAssertEqual($0 as? MIDICleanup.Refusal, .connected) }
        XCTAssertThrowsError(try MIDICleanup.remove(device("IAC Driver", maker: "Apple Inc.", offline: true))) { XCTAssertEqual($0 as? MIDICleanup.Refusal, .system) }
        XCTAssertThrowsError(try MIDICleanup.remove(device("Fixture that does not exist", offline: true))) { XCTAssertEqual($0 as? MIDICleanup.Refusal, .vanished) }
    }
}
