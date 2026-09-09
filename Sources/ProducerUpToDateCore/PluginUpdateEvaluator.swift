// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

public enum PluginUpdateEvaluator {
    public static func evaluate(
        _ product: NormalizedPluginProduct,
        catalogue: [PluginReleaseRecord],
        now: Date = Date(),
        confirmedCatalogueID: String? = nil
    ) -> PluginUpdateResult {
        // A user confirmation may stand in for the name match, never for the vendor-line check.
        let confirmed = confirmedCatalogueID.flatMap { id in
            IdentityConfirmations.candidates(for: product, in: catalogue).first { $0.catalogueID == id }
        }
        let matched = confirmed ?? (product.requiresVerification ? nil : catalogue.first(where: { matches(product, release: $0) }))
        guard let release = matched else {
            // "Identity unconfirmed" is only honest when there is something to confirm: at least one
            // catalogued product from the same vendor line. Otherwise the product is simply not catalogued.
            let confirmable = product.requiresVerification && !IdentityConfirmations.candidates(for: product, in: catalogue).isEmpty
            return PluginUpdateResult(
                product: product,
                updateState: .notChecked,
                reason: confirmable ? .identityNeedsReview : .noReviewedRelease
            )
        }

        let state: UpdateCheckState
        var reason: PluginUpdateReason?
        if EvidenceFreshness.isFresh(release.checkedOn, now: now),
           product.bundles.allSatisfy({ $0.displayVersion != nil }),
           product.installedVersions.count == 1,
           let installedVersion = product.installedVersions.first,
           let comparableInstalled = VersionComparator.releaseValue(installedVersion) {
            switch VersionComparator.compare(
                comparableInstalled,
                release.latestVersion
            ) {
            case .older:
                state = .updateAvailable
            case .equal:
                state = .current
            case .newer:
                state = .unavailable
                reason = .installedVersionAhead
            case .incomparable:
                state = .unavailable
                reason = .incomparableVersions
            }
        } else {
            state = .unavailable
            if !EvidenceFreshness.isFresh(release.checkedOn, now: now) { reason = .staleEvidence }
            else if product.bundles.contains(where: { $0.displayVersion == nil }) { reason = .missingReleaseVersion }
            else if product.installedVersions.count != 1 { reason = .differentInstalledVersions }
            else { reason = .incomparableVersions }
        }

        var result = PluginUpdateResult(
            product: product,
            updateState: state,
            latestVersion: release.latestVersion,
            sourceURL: release.sourceURL,
            checkedOn: release.checkedOn,
            reason: reason,
            identityConfirmedByUser: confirmed != nil
        )
        result.checkMethod = release.checkMethod
        return result
    }

    public static func matches(
        _ product: NormalizedPluginProduct,
        release: PluginReleaseRecord
    ) -> Bool {
        let identifiers = product.bundles.compactMap(\.bundleIdentifier)
        guard release.vendorIdentifierPrefixes.contains(where: { prefix in
            identifiers.count == product.bundles.count && identifiers.allSatisfy { identifier in
                identifier.lowercased().hasPrefix(prefix.lowercased())
            }
        }) else {
            return false
        }

        let productKey = canonicalName(product.name)
        return release.productAliases.contains {
            canonicalName($0) == productKey
        }
    }

    private static func canonicalName(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }


}
