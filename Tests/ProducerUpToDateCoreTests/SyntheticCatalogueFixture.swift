// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation
@testable import ProducerUpToDateCore

/// Invented records for catalogue validation; no resource files or current vendor releases.
/// The official host exercises the production URL allowlist only.
enum SyntheticCatalogueFixture {
    static let day = "2026-09-05"
    static let now = EvidenceFreshness.date("2026-09-08")!
    static let source = URL(string: "https://www.fabfilter.com/fixture")!

    static func release(_ name: String, version: String = "2.0", prefix: String = "com.example.",
                        family: String? = nil, edition: Int? = nil) -> PluginReleaseRecord {
        .init(vendorIdentifierPrefixes: [prefix], productAliases: [name], latestVersion: version,
              sourceURL: source, checkedOn: day, family: family, edition: edition)
    }

    static var snapshot: CatalogueSnapshot {
        let plugins = [release("Fixture EQ 3", version: "3.0", family: "fixture:eq", edition: 3),
                       release("Fixture EQ 4", version: "4.0", family: "fixture:eq", edition: 4),
                       release("Fixture Dynamics 3", version: "3.0", family: "fixture:dynamics", edition: 3),
                       release("Other Fixture", prefix: "org.example.")]
        return .init(schemaVersion: 1, sequence: 1, generatedOn: day, plugins: plugins,
            daws: [.init(definitionID: "fixture-daw", latestVersion: "12.0", sourceURL: source, checkedOn: day, majorVersion: 12)],
            drivers: [.init(bundleIdentifier: "com.example.driver", latestVersion: "2.0", sourceURL: source, checkedOn: day)],
            architectures: [.init(vendorIdentifierPrefixes: ["com.example."], exactProductAliases: ["Fixture EQ 4"],
                minimumNativeVersion: "4.0", recommendedVersion: "4.0", nativeFormats: [.audioUnit, .vst3], sourceURL: source, checkedOn: day)],
            releaseNotes: [.init(productID: plugins[0].catalogueID, version: "3.0", checkedOn: day,
                                highlights: ["Synthetic release note."], sourceURL: source)])
    }

    static func payload(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func sign(_ payload: Data, key: Curve25519.Signing.PrivateKey) throws -> Data {
        try JSONEncoder().encode(SignedCatalogueEnvelope(payload: payload, signature: key.signature(for: payload)))
    }
}
