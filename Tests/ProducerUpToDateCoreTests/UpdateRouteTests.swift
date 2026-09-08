// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class UpdateRouteTests: XCTestCase {
    private let now = EvidenceFreshness.date("2026-09-06")!
    private func bundle(_ name: String, id: String?, version: String = "1.0", links: [DeclaredProductLink] = []) -> PluginBundleRecord {
        PluginBundleRecord(id: "\(name)-\(id ?? "none")", name: name, vendor: nil, format: .audioUnit, bundleIdentifier: id, displayVersion: version,
            buildVersion: nil, path: URL(fileURLWithPath: "/Library/\(name).component"), executablePath: nil, architectures: [.arm64],
            fileSize: nil, modifiedAt: nil, evidence: [], issues: [], declaredLinks: links)
    }
    private func product(_ name: String, vendor: String? = "Vendor", ids: [String?], unverified: Bool = false, version: String = "1.0", links: [DeclaredProductLink] = []) -> NormalizedPluginProduct {
        NormalizedPluginProduct(id: "id-\(name)", name: name, vendor: vendor, bundles: ids.map { bundle(name, id: $0, version: version, links: links) },
            confidence: unverified ? .low : .high, matchEvidence: [], requiresVerification: unverified)
    }
    private func record(_ alias: String, prefix: String, version: String = "1.0", checkedOn: String = "2026-09-05") -> PluginReleaseRecord {
        .init(vendorIdentifierPrefixes: [prefix], productAliases: [alias], latestVersion: version,
              sourceURL: URL(string: "https://www.fabfilter.com/download")!, checkedOn: checkedOn)
    }

    func testRoutesAndLabelsCoverEveryProduct() {
        let catalogue = [record("Pro-Q 4", prefix: "com.fabfilter.", version: "4.13")]
        let compared = PluginUpdateEvaluator.evaluate(product("Pro-Q 4", ids: ["com.fabfilter.proq4"], version: "4.13"), catalogue: catalogue, now: now)
        XCTAssertEqual(compared.route, .catalogue)
        XCTAssertEqual(compared.resultLabel, "Matches listed version")
        let behind = PluginUpdateEvaluator.evaluate(product("Pro-Q 4", ids: ["com.fabfilter.proq4"], version: "4.10"), catalogue: catalogue, now: now)
        XCTAssertEqual(behind.resultLabel, "Update available")
        let ahead = PluginUpdateEvaluator.evaluate(product("Pro-Q 4", ids: ["com.fabfilter.proq4"], version: "4.20"), catalogue: catalogue, now: now)
        XCTAssertEqual(ahead.route, .catalogue)
        XCTAssertEqual(ahead.resultLabel, "Newer than catalogue")
        let managed = PluginUpdateEvaluator.evaluate(product("Pigments", ids: ["com.arturia.pigments", "com.arturia.pigments.vst3"]), catalogue: catalogue, now: now)
        XCTAssertEqual(managed.route.managerName, "Arturia Software Center")
        XCTAssertEqual(managed.resultLabel, "Managed by Arturia Software Center")
        let managedUnverified = PluginUpdateEvaluator.evaluate(product("Analog Lab", ids: ["com.arturia.analoglab"], unverified: true), catalogue: catalogue, now: now)
        XCTAssertEqual(managedUnverified.route.managerName, "Arturia Software Center", "The manager is the route even when identity is unconfirmed")
        let unconfirmed = PluginUpdateEvaluator.evaluate(product("Mystery", ids: ["com.fabfilter.mystery"], unverified: true), catalogue: catalogue, now: now)
        XCTAssertEqual(unconfirmed.route, .identityUnconfirmed)
        XCTAssertEqual(unconfirmed.resultLabel, "Identity unconfirmed")
        let website = PluginUpdateEvaluator.evaluate(product("Example Instrument", ids: ["com.example.instrument"], links: [DeclaredProductLink(kind: .website, value: "https://developer.example.com")!]), catalogue: catalogue, now: now)
        if case .website(let url) = website.route { XCTAssertEqual(url.host, "developer.example.com") } else { XCTFail("expected website route") }
        XCTAssertEqual(website.resultLabel, "Check vendor site")
        let nothing = PluginUpdateEvaluator.evaluate(product("Obscure", ids: ["com.nobody.obscure"]), catalogue: catalogue, now: now)
        XCTAssertEqual(nothing.route, .none)
        XCTAssertEqual(nothing.resultLabel, "Not in catalogue")
        let mixed = PluginUpdateEvaluator.evaluate(product("Mixed", ids: ["com.arturia.x", nil]), catalogue: catalogue, now: now)
        XCTAssertEqual(mixed.route, .none, "A bundle without an identifier cannot be attributed to a manager")

        let coverage = PluginUpdateCoverage(results: [compared, behind, ahead, managed, managedUnverified, unconfirmed, website, nothing, mixed])
        XCTAssertEqual(coverage.total, 9)
        XCTAssertEqual(coverage.compared, 2)
        XCTAssertEqual(coverage.managed, 2)
        XCTAssertEqual(coverage.websiteOnly, 1)
        XCTAssertEqual(coverage.identityUnconfirmed, 1)
        XCTAssertEqual(coverage.unresolved, 7)
        XCTAssertEqual(coverage.unrouted, 3, "ahead (catalogue, not compared), obscure and mixed")
    }

    func testIdentityConfirmationOnlyWithinTheVendorLine() throws {
        let catalogue = [record("Pro-Q 4", prefix: "com.fabfilter.", version: "4.13"), record("Snap Heap", prefix: "com.kilohearts.", version: "2.4.6")]
        let files = product("Unknown FabFilter thing", ids: ["com.fabfilter.aaa", "com.fabfilter.bbb"], unverified: true, version: "4.13")
        let candidates = IdentityConfirmations.candidates(for: files, in: catalogue)
        XCTAssertEqual(candidates.map(\.catalogueID), ["com.fabfilter.:Pro-Q 4"])
        XCTAssertEqual(PluginUpdateEvaluator.evaluate(files, catalogue: catalogue, now: now).updateState, .notChecked)
        let confirmed = PluginUpdateEvaluator.evaluate(files, catalogue: catalogue, now: now, confirmedCatalogueID: "com.fabfilter.:Pro-Q 4")
        XCTAssertEqual(confirmed.updateState, .current)
        XCTAssertTrue(confirmed.identityConfirmedByUser)
        XCTAssertEqual(confirmed.route, .catalogue)
        let crossVendor = PluginUpdateEvaluator.evaluate(files, catalogue: catalogue, now: now, confirmedCatalogueID: "com.kilohearts.:Snap Heap")
        XCTAssertEqual(crossVendor.updateState, .notChecked, "A confirmation outside the vendor line is ignored")
        XCTAssertFalse(crossVendor.identityConfirmedByUser)
        let stale = PluginUpdateEvaluator.evaluate(files, catalogue: catalogue, now: now, confirmedCatalogueID: "com.fabfilter.:Gone")
        XCTAssertEqual(stale.updateState, .notChecked, "A confirmation for a record no longer in the catalogue does nothing")
        XCTAssertTrue(IdentityConfirmations.candidates(for: product("Mixed", ids: ["com.fabfilter.x", nil], unverified: true), in: catalogue).isEmpty)
        let verified = PluginUpdateEvaluator.evaluate(product("Pro-Q 4", ids: ["com.fabfilter.proq4"], version: "4.13"), catalogue: catalogue, now: now, confirmedCatalogueID: "com.fabfilter.:Pro-Q 4")
        XCTAssertTrue(verified.identityConfirmedByUser, "An explicit confirmation is honoured even when the scanner agrees")
    }

    func testConfirmationStoreRoundTripAndBounds() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("identity.json")
        XCTAssertEqual(IdentityConfirmations.load(from: url), IdentityConfirmations())
        var store = IdentityConfirmations()
        try store.confirm(productID: "p1", catalogueID: "com.fabfilter.:Pro-Q 4")
        try store.save(to: url)
        XCTAssertEqual(IdentityConfirmations.load(from: url).catalogueID(for: "p1"), "com.fabfilter.:Pro-Q 4")
        store.remove(productID: "p1")
        XCTAssertNil(store.catalogueID(for: "p1"))
        XCTAssertThrowsError(try store.confirm(productID: "", catalogueID: "x"))
        XCTAssertThrowsError(try store.confirm(productID: "p", catalogueID: String(repeating: "x", count: 300)))
        var full = IdentityConfirmations(records: Dictionary(uniqueKeysWithValues: (0..<IdentityConfirmations.maximumEntries).map { ("p\($0)", "c") }))
        XCTAssertThrowsError(try full.confirm(productID: "overflow", catalogueID: "c"))
        XCTAssertNoThrow(try full.confirm(productID: "p1", catalogueID: "c2"), "Re-confirming an existing product is allowed at capacity")
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(IdentityConfirmations.load(from: url), IdentityConfirmations())
        try JSONEncoder().encode(IdentityConfirmations(records: ["": "x"])).write(to: url)
        XCTAssertEqual(IdentityConfirmations.load(from: url), IdentityConfirmations(), "Malformed entries invalidate the file")
    }
}
