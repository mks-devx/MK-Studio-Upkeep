// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore
final class DeclaredProductLinkTests: XCTestCase {
    func testScannerRetainsDeclaredLinksAndOldRecordsStillDecode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("Example.vst3")
        let resources = bundle.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleName": "Example", "CFBundleIdentifier": "com.example.instrument", "CFBundleVersion": "1", "SUFeedURL": "https://updates.example.com/feed.xml"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        try JSONSerialization.data(withJSONObject: ["Factory Info": ["URL": "https://developer.example.com"]]).write(to: resources.appendingPathComponent("moduleinfo.json"))
        let record = BundleMetadataReader().read(bundleURL: bundle, format: .vst3)
        XCTAssertEqual(record.declaredLinks?.count, 2)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        encoded.removeValue(forKey: "declaredLinks")
        let old = try JSONDecoder().decode(PluginBundleRecord.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertNil(old.declaredLinks)
    }
    func testDecoderCannotBypassDestinationValidation() throws {
        let bad = try JSONSerialization.data(withJSONObject: ["kind": "website", "url": "file:///private/example"])
        XCTAssertThrowsError(try JSONDecoder().decode(DeclaredProductLink.self, from: bad))
    }
    func testDiscoversStandardMetadataWithoutProductNames() {
        let result = DeclaredProductLink.extract(plist: ["SUFeedURL": "https://updates.example.com/appcast.xml"],
            moduleInfo: ["Factory Info": ["URL": "https://developer.example.com"]])
        XCTAssertEqual(result.map(\.kind), [.updateFeed, .website])
        XCTAssertEqual(DeclaredProductLink.extract(plist: nil, moduleInfo: nil), [])
    }
    func testRejectsCredentialsPrivateAddressesAndQueryTokens() {
        for value in ["file:///etc/passwd", "javascript:alert(1)", "https://localhost/feed", "https://127.0.0.1/feed",
                      "https://device.local/feed", "https://user:secret@example.com/feed", "https://example.com/feed?licence=secret",
                      "https://example.com:9000/feed", "https://[::1]/feed", "https://example.com/feed#token"] {
            XCTAssertNil(DeclaredProductLink(kind: .website, value: value), value)
        }
    }
    func testMissingAndMalformedFieldsDoNotCreateLinks() {
        XCTAssertEqual(DeclaredProductLink.extract(plist: ["SUFeedURL": ["not": "text"]], moduleInfo: ["Factory Info": ["URL": 12]]), [])
    }
}
