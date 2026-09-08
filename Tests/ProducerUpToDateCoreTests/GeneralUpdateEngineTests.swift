// SPDX-License-Identifier: MPL-2.0
import XCTest
@testable import ProducerUpToDateCore

final class GeneralUpdateEngineTests: XCTestCase {
    typealias E = GeneralUpdateEngine
    private func source(_ id: String = "feed", reviewed: Bool = true, reader: E.Reader = .json) -> E.Source {
        .init(id: id, endpoint: URL(string: "https://vendor.example/\(id)")!, reader: reader,
              accessBasis: reviewed ? "Synthetic fixture only; no live permission implied" : nil)
    }
    private func product(_ id: String, source: String = "feed", edition: String = "standard") -> E.Product {
        .init(id: id, bundleIDs: ["example.\(id)"], edition: edition, format: "VST3", major: 1, sourceID: source)
    }
    private func install(_ id: String, version: String = "1.0") -> E.Installation {
        .init(bundleID: "example.\(id)", format: "VST3", version: version)
    }
    private func data(_ ids: [String], platform: String = "macOS", edition: String = "standard", version: String = "1.2") throws -> Data {
        try JSONEncoder().encode(ids.map { E.Release(productID: $0, edition: edition, format: "VST3", platform: platform, version: version) })
    }
    func testDifferentInventoriesUseSameRegistryAndOneRequestPerSource() async throws {
        let registry = E.Registry(products: [product("synth"), product("delay"), product("eq")], sources: [source()])
        let bytes = try data(["synth", "delay", "eq"])
        let counter = Counter()
        let first = try await E.check([install("synth"), install("delay", version: "1.2")], registry: registry) { url in
            XCTAssertEqual(url.absoluteString, "https://vendor.example/feed")
            await counter.add(); return bytes
        }
        XCTAssertEqual(first.map(\.status), [.update("1.2"), .matches("1.2")])
        let calls = await counter.value
        XCTAssertEqual(calls, 1)
        let stef = try await E.check([install("eq"), install("unknown")], registry: registry) { _ in bytes }
        XCTAssertEqual(stef.map(\.status), [.update("1.2"), .unknownIdentity])
    }
    func testUnreviewedAndAmbiguousSourcesNeverFetch() async throws {
        let registry = E.Registry(products: [product("synth")], sources: [source(reviewed: false)])
        let result = try await E.check([install("synth")], registry: registry) { _ in XCTFail("No network allowed"); return Data() }
        XCTAssertEqual(result.first?.status, .sourceNotReviewed)
        let conflict = E.Product(id: "other", bundleIDs: ["example.synth"], edition: "GE", format: "VST3", major: 1, sourceID: "feed")
        let ambiguous = try await E.check([install("synth")], registry: .init(products: registry.products + [conflict], sources: [source()])) { _ in XCTFail("Ambiguous identity"); return Data() }
        XCTAssertEqual(ambiguous.first?.status, .ambiguousIdentity)
    }
    func testWrongPlatformEditionMajorAndPrereleaseDoNotBecomeCurrent() async throws {
        let registry = E.Registry(products: [product("synth")], sources: [source()])
        let feeds = [try data(["synth"], platform: "Windows"), try data(["synth"], edition: "GE"), try data(["synth"], version: "2.0"), try data(["synth"], version: "1.3-beta1")]
        for bytes in feeds {
            let results = try await E.check([install("synth")], registry: registry) { _ in bytes }
            XCTAssertEqual(results.first?.status, .noMatchingRelease)
        }
    }
    func testFailureIsolationAndNoRepeatedFetchForFailedSource() async throws {
        let registry = E.Registry(products: [product("synth"), product("delay"), product("eq", source: "second")], sources: [source(), source("second")])
        let bytes = try data(["eq"])
        let result = try await E.check([install("synth"), install("delay"), install("eq")], registry: registry) { url in
            if url.lastPathComponent == "feed" { throw E.Failure.invalidFeed }; return bytes
        }
        XCTAssertEqual(result.map(\.status), [.sourceFailed, .sourceFailed, .update("1.2")])
    }
    func testCancellationPropagatesAndDoesNotBecomeFailedResult() async throws {
        do {
            _ = try await E.check([install("synth")], registry: .init(products: [product("synth")], sources: [source()])) { _ in throw CancellationError() }
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }
    func testSparkleNamespaceAndVersionSelection() async throws {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:shortVersionString>1.9</sparkle:shortVersionString></item>
        <item><sparkle:shortVersionString>1.10</sparkle:shortVersionString></item>
        <item><sparkle:shortVersionString>1.99</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel></item>
        <item><sparkle:shortVersionString>1.98</sparkle:shortVersionString><enclosure sparkle:os="windows"/></item>
        <item><shortVersionString>1.97</shortVersionString></item>
        </channel></rss>
        """
        let result = try await E.check([install("synth")], registry: .init(products: [product("synth")], sources: [source(reader: .sparkle)])) { _ in Data(xml.utf8) }
        XCTAssertEqual(result.first?.status, .update("1.10"))
    }
    func testMalformedAndOversizedFeedsAndRegistryRejected() throws {
        XCTAssertThrowsError(try E.parse(Data(repeating: 0, count: E.maximumBytes + 1), source: source(), products: []))
        XCTAssertThrowsError(try E.parse(Data("<!DOCTYPE rss><rss/>".utf8), source: source(reader: .sparkle), products: [product("synth")]))
        XCTAssertThrowsError(try E.validate(.init(products: [], sources: [source(), source()])))
        let unsafe = E.Source(id: "bad", endpoint: URL(string: "http://localhost/feed")!, reader: .json, accessBasis: "fixture")
        XCTAssertThrowsError(try E.validate(.init(products: [], sources: [unsafe])))
    }
}
private actor Counter {
    var value = 0
    func add() { value += 1 }
}
