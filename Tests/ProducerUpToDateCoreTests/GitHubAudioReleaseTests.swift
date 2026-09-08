// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class GitHubAudioReleaseTests: XCTestCase {
    typealias E = GeneralUpdateEngine
    private let source = E.Source(id: "fixture", endpoint: URL(string: "https://api.github.com/repos/example/synth/releases/latest")!, reader: .githubLatest, accessBasis: "Synthetic test", macAssetTemplate: "Synth-Mac-{version}.dmg")
    private let product = E.Product(id: "synth", bundleIDs: ["example.synth"], edition: "standard", format: "VST3", major: 1, sourceID: "fixture")
    private func data(tag: String = "v1.2.0", asset: String = "Synth-Mac-1.2.0.dmg", prefix: String = "https://github.com/example/synth", beta: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name":tag,"draft":false,"prerelease":beta,
            "html_url":"\(prefix)/releases/tag/\(tag)", "assets":[["name":asset,"browser_download_url":"\(prefix)/releases/download/\(tag)/\(asset)"]]])
    }
    func testStableMacAssetAgreement() throws {
        XCTAssertEqual(try E.parse(data(), source: source, products: [product]).first?.version, "1.2.0")
    }
    func testNightlyDespiteFalsePrereleaseFlagAndOtherInvalidTags() throws {
        for tag in ["Nightly", "v1.3.0-beta1", "release-1.2.0"] {
            XCTAssertThrowsError(try E.parse(data(tag: tag), source: source, products: [product]))
        }
        XCTAssertThrowsError(try E.parse(data(beta: true), source: source, products: [product]))
    }
    func testWrongPlatformWrongVersionAndSpoofedRepository() throws {
        for asset in ["Synth-Windows-1.2.0.exe", "Synth-Mac-1.1.0.dmg"] {
            XCTAssertThrowsError(try E.parse(data(asset: asset), source: source, products: [product]))
        }
        XCTAssertThrowsError(try E.parse(data(prefix: "https://github.com/attacker/synth"), source: source, products: [product]))
    }
}
