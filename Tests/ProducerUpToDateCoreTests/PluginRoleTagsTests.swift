// SPDX-License-Identifier: BUSL-1.1
import XCTest
@testable import ProducerUpToDateCore

final class PluginRoleTagsTests: XCTestCase {
    func testMultipleRolesAndDuplicatesArePreservedAsDistinctTags() {
        let e = VersionEvidence(kind: .vst3ModuleInfo, field: "Classes[0].Sub Categories", value: "Fx|EQ| Dynamics |EQ|Unknown")
        XCTAssertEqual(PluginRoleTags.classify(evidence: [e, e]), ["Dynamics", "EQ"])
    }
    func testNamesAndMissingMetadataCannotInventRoles() {
        XCTAssertEqual(PluginRoleTags.classify(evidence: []), [])
        XCTAssertEqual(PluginRoleTags.classify(evidence: [.init(kind: .inferred, field: "Name", value: "EQ")]), [])
        XCTAssertEqual(PluginRoleTags.classify(evidence: [.init(kind: .vst3ModuleInfo, field: "Classes[0].Name", value: "EQ")]), [])
    }
    func testInstrumentRolesCanCoexist() {
        XCTAssertEqual(PluginRoleTags.classify(evidence: [.init(kind: .vst3ModuleInfo, field: "Classes[0].Sub Categories", value: "Instrument|Synth|Sampler")]), ["Sampler", "Synthesizer"])
    }
}
