// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import UpdateEnginePrototypeSupport

final class FeedTransportTests: XCTestCase {
    func testLocalSpecialAndAmbiguousIPv4AddressesAreRejected() {
        for ip in ["127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.0.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "198.18.0.1", "192.0.2.1", "198.51.100.1", "203.0.113.1", "224.0.0.1", "255.255.255.255", "001.2.3.4", "1.2.3", "::1"] {
            XCTAssertFalse(PublicFeedTransport.isPublicIPv4(ip), ip)
        }
        XCTAssertTrue(PublicFeedTransport.isPublicIPv4("8.8.8.8"))
    }
    func testURLPolicyRejectsCredentialsParametersAndNonHTTPS() {
        for raw in ["http://updates.example.com/feed", "https://user:pass@updates.example.com/feed", "https://updates.example.com/feed?token=secret", "https://updates.example.com:8443/feed", "file:///tmp/feed", "https://localhost/feed", "https://device.local/feed", "https://127.0.0.1/feed", "https://updates.example.com./feed"] {
            XCTAssertFalse(PublicFeedTransport.acceptedURL(URL(string: raw)!), raw)
        }
    }
    func testTransportPinsPublicDestinationAndDoesNotFollowRedirects() throws {
        let url = URL(string: "https://updates.example.com/feed.xml")!
        let args = try PublicFeedTransport.arguments(url: url, address: "8.8.8.8")
        XCTAssertEqual(args.first, "-q")
        XCTAssertTrue(args.contains("updates.example.com:443:8.8.8.8"))
        XCTAssertTrue(args.contains("--globoff"))
        XCTAssertTrue(args.contains("--ipv4"))
        XCTAssertFalse(args.contains("--location"))
        XCTAssertFalse(args.contains("--insecure"))
        XCTAssertThrowsError(try PublicFeedTransport.arguments(url: url, address: "127.0.0.1"))
        XCTAssertThrowsError(try PublicFeedTransport.fetch(url, allowNetwork: false))
    }
    func testResponseStatusAndTypeAreRequired() throws {
        XCTAssertEqual(try PublicFeedTransport.body(from: Data("<rss/>\n200\napplication/xml; charset=utf-8".utf8)), Data("<rss/>".utf8))
        for tail in ["302\napplication/xml", "206\napplication/xml", "429\napplication/xml", "200\ntext/html", "200\napplication/octet-stream"] {
            XCTAssertThrowsError(try PublicFeedTransport.body(from: Data("<rss/>\n\(tail)".utf8)))
        }
    }
    func testHTMLResponsePolicyIsExplicit() throws {
        XCTAssertEqual(try PublicFeedTransport.body(from: Data("<html/>\n200\ntext/html; charset=utf-8".utf8), html: true), Data("<html/>".utf8))
        for tail in ["302\ntext/html", "429\ntext/html", "200\napplication/xml", "200\napplication/octet-stream"] {
            XCTAssertThrowsError(try PublicFeedTransport.body(from: Data("body\n\(tail)".utf8), html: true))
        }
    }
    func testProcessOutputAndTimeAreBounded() {
        XCTAssertThrowsError(try BoundedProcess.read(executable: "/usr/bin/yes", arguments: [], maximumBytes: 100, timeout: 1))
        let start = Date()
        XCTAssertThrowsError(try BoundedProcess.read(executable: "/bin/sleep", arguments: ["2"], maximumBytes: 100, timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }
    func testCancellationStopsAnActiveRead() async {
        let task = Task.detached { try BoundedProcess.read(executable: "/bin/sleep", arguments: ["5"], maximumBytes: 100, timeout: 6) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
