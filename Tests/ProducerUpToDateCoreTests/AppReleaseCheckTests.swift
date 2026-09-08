// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class AppReleaseCheckTests: XCTestCase {
    private let source = AppReleaseCheck.Source("example/studio-upkeep")!
    private func release(_ tag: String, beta: Bool = false, draft: Bool = false, page: String? = nil) -> [String: Any] {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ["assets": ["MK-Studio-Upkeep-\(version)-macOS.dmg", "SHA256SUMS.txt"].map { name in
            ["name": name, "state": "uploaded", "size": 1024,
             "browser_download_url": "https://github.com/example/studio-upkeep/releases/download/\(tag)/\(name)"] as [String: Any]
        }, "tag_name": tag, "prerelease": beta, "draft": draft,
         "html_url": page ?? "https://github.com/example/studio-upkeep/releases/tag/\(tag)"]
    }
    private func check(_ releases: [[String: Any]], installed: String = "0.2.0", betas: Bool = true) throws -> AppReleaseCheck.Result {
        try AppReleaseCheck.evaluate(JSONSerialization.data(withJSONObject: releases), source: source, installed: installed, includeBetas: betas)
    }
    func testVersionOrderingAndCurrentAndAhead() throws {
        let releases = [release("v0.2.0"), release("v0.10.0"), release("v0.3.0")]
        XCTAssertEqual(try check(releases), .update(version: "v0.10.0", page: URL(string: "https://github.com/example/studio-upkeep/releases/tag/v0.10.0")!))
        XCTAssertEqual(try check(releases, installed: "0.10"), .current(version: "v0.10.0"))
        XCTAssertEqual(try check(releases, installed: "0.11.0"), .ahead(version: "v0.10.0"))
    }
    func testBetaPreferenceAndDraftExclusion() throws {
        let releases = [release("v0.2.0"), release("v0.3.0-beta.1", beta: true), release("v99.0", draft: true)]
        XCTAssertEqual(try check(releases, betas: false), .current(version: "v0.2.0"))
        guard case .update(let version, _) = try check(releases) else { return XCTFail("Expected beta update") }
        XCTAssertEqual(version, "v0.3.0-beta.1")
        XCTAssertEqual(try check([release("v0.3.0-beta.1")], betas: false), .noReleases)
    }
    func testNoReleaseIsNotCurrent() throws {
        XCTAssertEqual(try check([]), .noReleases)
        XCTAssertEqual(try check([release("v1.0", draft: true)]), .noReleases)
    }
    func testRejectsAmbiguousVersionsAndUntrustedLinks() {
        XCTAssertThrowsError(try check([release("latest")]))
        XCTAssertThrowsError(try check([release("v1.0")], installed: "Development"))
        for page in ["https://evil.example/update", "https://github.com/other/repo/releases/tag/v1.0", "https://github.com@example.org/update", "https://github.com/example/studio-upkeep/releases/tag/v1.0?redirect=elsewhere"] {
            XCTAssertThrowsError(try check([release("v1.0", page: page)]))
        }
    }
    func testRejectsMissingOrUnsafeSource() {
        for value in [nil, "", "https://github.com/example/repo", "example/../repo", "example/repo?x=y", "example/repo\n"] as [String?] {
            XCTAssertNil(AppReleaseCheck.Source(value))
        }
        XCTAssertEqual(source.endpoint.host, "api.github.com")
    }
    func testRejectsMalformedOversizedAndTruncatedLists() {
        for data in [Data("{}".utf8), Data(repeating: 32, count: AppReleaseCheck.maximumBytes + 1)] {
            XCTAssertThrowsError(try AppReleaseCheck.evaluate(data, source: source, installed: "0.2.0", includeBetas: true))
        }
        XCTAssertThrowsError(try check(Array(repeating: release("v1.0"), count: 101)))
    }
    func testSameAndNewerBetaVersions() throws {
        let first = release("v0.2.0-beta.1", beta: true)
        XCTAssertEqual(try check([first], installed: "0.2.0-beta.1"), .current(version: "v0.2.0-beta.1"))
        guard case .update = try check([first, release("v0.2.0-beta.2", beta: true)], installed: "0.2.0-beta.1") else {
            return XCTFail("A newer beta must be offered")
        }
    }

    func testOnlyCompleteTrustedMacDownloadsAreOffered() throws {
        for kind in ["missing", "empty", "installer-only", "checksum-only", "uploading", "zero-size", "external", "wrong-version"] {
            var candidate = release("v0.3.0")
            var assets = candidate["assets"] as! [[String: Any]]
            switch kind {
            case "missing": candidate.removeValue(forKey: "assets")
            case "empty": assets = []
            case "installer-only": assets.removeLast()
            case "checksum-only": assets.removeFirst()
            case "uploading": assets[0]["state"] = "starter"
            case "zero-size": assets[0]["size"] = 0
            case "external": assets[0]["browser_download_url"] = "https://untrusted.example/installer.dmg"
            case "wrong-version": assets[0]["name"] = "MK-Studio-Upkeep-0.1.0-macOS.dmg"
            default: break
            }
            if kind != "missing" { candidate["assets"] = assets }
            XCTAssertEqual(try check([candidate]), .noReleases, kind)
            XCTAssertEqual(try check([candidate, release("v0.2.0")]), .current(version: "v0.2.0"), kind)
        }
    }

}
