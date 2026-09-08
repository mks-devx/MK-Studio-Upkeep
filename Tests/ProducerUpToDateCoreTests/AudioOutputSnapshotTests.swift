// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class AudioOutputSnapshotTests: XCTestCase {
    private final class Reader: AudioOutputReading {
        var device: UInt32? = 42
        var secondDevice: UInt32? = 42
        var calls = 0
        var alive: Bool? = true
        var rate: Double? = 48_000
        var frames: UInt32? = 256
        var depths: [UInt32]? = [24, 24]
        var readIDs: [UInt32] = []
        func defaultOutput() -> UInt32? { calls += 1; return calls == 1 ? device : secondDevice }
        func isAlive(_ id: UInt32) -> Bool? { alive }
        func name(_ id: UInt32) -> String? { readIDs.append(id); return "Example Audio Interface" }
        func sampleRate(_ id: UInt32) -> Double? { readIDs.append(id); return rate }
        func bufferFrames(_ id: UInt32) -> UInt32? { readIDs.append(id); return frames }
        func bitDepths(_ id: UInt32) -> [UInt32]? { readIDs.append(id); return depths }
    }

    func testReadsOnlyTheDefaultOutputAndDeduplicatesStreamDepths() throws {
        let reader = Reader()
        let value = try XCTUnwrap(AudioOutputSnapshot.read(using: reader))
        XCTAssertEqual(value.name, "Example Audio Interface")
        XCTAssertEqual(value.sampleRate, 48_000)
        XCTAssertEqual(value.bufferFrames, 256)
        XCTAssertEqual(value.bitDepths, [24])
        XCTAssertEqual(Set(reader.readIDs), [42])
    }
    func testMixedStreamDepthsArePreserved() {
        let reader = Reader(); reader.depths = [32, 16, 24, 32]
        XCTAssertEqual(AudioOutputSnapshot.read(using: reader)?.bitDepths, [16, 24, 32])
    }
    func testMissingOrInvalidPropertiesRemainUnavailable() {
        for rate in [Double.nan, .infinity, 0, -1] {
            let reader = Reader(); reader.rate = rate; reader.frames = 0; reader.depths = [24, 0]
            let value = AudioOutputSnapshot.read(using: reader)
            XCTAssertNotNil(value)
            XCTAssertNil(value?.sampleRate)
            XCTAssertNil(value?.bufferFrames)
            XCTAssertNil(value?.bitDepths)
        }
        let reader = Reader(); reader.rate = nil; reader.frames = nil; reader.depths = nil
        XCTAssertNil(AudioOutputSnapshot.read(using: reader)?.bitDepths)
    }
    func testMissingOrDisconnectedOutputDoesNotChooseAnotherDevice() {
        for id: UInt32? in [nil, 0] {
            let reader = Reader(); reader.device = id
            XCTAssertNil(AudioOutputSnapshot.read(using: reader))
            XCTAssertTrue(reader.readIDs.isEmpty)
        }
        let reader = Reader(); reader.alive = false
        XCTAssertNil(AudioOutputSnapshot.read(using: reader))
    }
    func testSwitchDuringReadDiscardsTheOldDeviceSnapshot() {
        let reader = Reader(); reader.secondDevice = 99
        XCTAssertNil(AudioOutputSnapshot.read(using: reader))
    }
}
