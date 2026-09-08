// SPDX-License-Identifier: MPL-2.0
import Foundation
import XCTest
@testable import ProducerUpToDateCore
final class ProductWebSearchTests: XCTestCase {
    func testAnyProductCanPrepareAQueryWithoutARegistry() {
        let query = ProductWebSearch.suggestedQuery(product: "Example Synth 12", developer: "Example Audio")
        XCTAssertEqual(query, "Example Synth 12 Example Audio official download release notes macOS")
        XCTAssertFalse(ProductWebSearch.suggestedQuery(product: "Unlisted instrument", developer: nil).isEmpty)
    }
    func testProviderAndQueryAreKeptSeparate() throws {
        let query = "Example & Another? #test + 🎵"
        for provider in ProductSearchProvider.allCases {
            let url = try XCTUnwrap(provider.url(query: query))
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.host, provider.destination.host)
            XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: query)])
            XCTAssertEqual(components.scheme, "https")
        }
    }
    func testRejectsEmptyOversizedAndControlCharacterQueries() {
        for provider in ProductSearchProvider.allCases {
            for query in [" ", String(repeating: "a", count: 513), "Example\u{0000}test"] { XCTAssertNil(provider.url(query: query)) }
        }
    }
    func testMetadataCannotChangeTheSearchDestination() throws {
        let query = ProductWebSearch.suggestedQuery(product: "https://evil.example/?q=bad", developer: "&q=override")
        let url = try XCTUnwrap(ProductSearchProvider.duckDuckGo.url(query: query))
        XCTAssertEqual(url.host, "duckduckgo.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count, 1)
    }
}
