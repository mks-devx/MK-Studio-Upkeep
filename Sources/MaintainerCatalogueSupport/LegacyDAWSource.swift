// SPDX-License-Identifier: MPL-2.0
import Foundation
import ProducerUpToDateCore

extension DAWUpdateSource {
    /// The reader mapped to this installation. By default only sources the app may request
    /// are returned; `includeInactive` exposes the mapping for fixtures and tooling.
    public static func checker(for daw: InstalledDAWRecord, includeInactive: Bool = false) -> DirectVendor? {
        guard !daw.identityIsInferred else { return nil }
        let source = DirectVendor.allCases.first { $0.dawDefinitionID == daw.definitionID }
        if source == .live, daw.displayVersion.flatMap(VersionComparator.releaseValue).flatMap(VersionComparator.parse)?.numbers.first != 12 { return nil }
        if source == .reason, daw.conciseInstalledVersion.flatMap(VersionComparator.parse)?.numbers.first != 14 { return nil }
        guard let source, includeInactive || source.isActive else { return nil }
        return source
    }

}
