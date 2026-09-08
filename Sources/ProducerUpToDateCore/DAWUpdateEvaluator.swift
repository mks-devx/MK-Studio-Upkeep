// SPDX-License-Identifier: BUSL-1.1
import Foundation

public enum DAWUpdateEvaluator {
    public static func evaluate(
        _ installed: InstalledDAWRecord,
        catalogue: [DAWReleaseRecord],
        now: Date = Date()
    ) -> InstalledDAWRecord {
        guard let release = catalogue.first(where: {
            $0.definitionID == installed.definitionID
        }) else {
            return installed.withoutUpdateEvidence()
        }

        if let major = release.majorVersion,
           installed.conciseInstalledVersion.flatMap(VersionComparator.parse)?.numbers.first != major {
            return installed.withoutUpdateEvidence()
        }
        let state: UpdateCheckState
        if !installed.identityIsInferred,
           EvidenceFreshness.isFresh(release.checkedOn, now: now),
           let installedVersion = installed.displayVersion,
           let comparableInstalled = VersionComparator.releaseValue(installedVersion) {
            switch VersionComparator.compare(
                comparableInstalled,
                release.latestVersion
            ) {
            case .older:
                state = .updateAvailable
            case .equal:
                state = .current
            case .newer, .incomparable:
                state = .unavailable
            }
        } else {
            state = .unavailable
        }

        var result = InstalledDAWRecord(
            id: installed.id,
            definitionID: installed.definitionID,
            name: installed.name,
            vendor: installed.vendor,
            bundleIdentifier: installed.bundleIdentifier,
            displayVersion: installed.displayVersion,
            buildVersion: installed.buildVersion,
            path: installed.path,
            executablePath: installed.executablePath,
            architectures: installed.architectures,
            identityIsInferred: installed.identityIsInferred,
            installedFromAppStore: installed.installedFromAppStore,
            updateState: state,
            latestVersion: release.latestVersion,
            updateSourceURL: release.sourceURL,
            updateCheckedOn: release.checkedOn
        )
        result.checkMethod = release.checkMethod
        return result
    }


}
