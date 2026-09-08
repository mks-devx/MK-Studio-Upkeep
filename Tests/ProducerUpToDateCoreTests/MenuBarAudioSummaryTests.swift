// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class MenuBarAudioSummaryTests: XCTestCase {
    func testValuesHaveUnitsAndPreserveFractionalSampleRate() {
        let value = AudioOutputSnapshot(name: "Example Output", sampleRate: 44_100, bufferFrames: 128, bitDepths: [24])
        XCTAssertEqual(MenuBarAudioSummary.title(for: value, locale: Locale(identifier: "en_GB")), "44.1 kHz · 24-bit · 128 fr")
        XCTAssertTrue(MenuBarAudioSummary.detail(for: value).contains("macOS output: Example Output"))
        XCTAssertTrue(MenuBarAudioSummary.detail(for: value).contains("128 frames"))
    }
    func testMissingValuesNeverBecomeZeroOrDefaultSettings() {
        let value = AudioOutputSnapshot(name: "Example Output", sampleRate: nil, bufferFrames: nil, bitDepths: nil)
        XCTAssertEqual(MenuBarAudioSummary.title(for: value), "— kHz · — bit · — fr")
        XCTAssertEqual(MenuBarAudioSummary.title(for: nil), "Audio unavailable")
    }
    func testMixedDepthsAreNotPresentedAsOneDepth() {
        let value = AudioOutputSnapshot(name: "Example Aggregate", sampleRate: 48_000, bufferFrames: 512, bitDepths: [16, 24])
        XCTAssertTrue(MenuBarAudioSummary.title(for: value).contains("mixed bits"))
        XCTAssertTrue(MenuBarAudioSummary.detail(for: value).contains("16-bit / 24-bit"))
    }
}
