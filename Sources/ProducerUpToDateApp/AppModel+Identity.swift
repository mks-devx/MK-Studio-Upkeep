// SPDX-License-Identifier: BUSL-1.1
import AppKit
import Combine
import Foundation
import ProducerUpToDateCore

/// Evaluation with the user's local identity confirmations.
extension AppModel {
    func evaluate(_ product: NormalizedPluginProduct) -> PluginUpdateResult {
        PluginUpdateEvaluator.evaluate(product, catalogue: pluginReleases,
                                       confirmedCatalogueID: identityConfirmations.catalogueID(for: product.id))
    }

    func identityCandidates(for product: NormalizedPluginProduct) -> [PluginReleaseRecord] {
        IdentityConfirmations.candidates(for: product, in: pluginReleases)
    }

    func confirmIdentity(of product: NormalizedPluginProduct, as record: PluginReleaseRecord) {
        guard identityCandidates(for: product).contains(record) else { return }
        var confirmations = identityConfirmations
        guard (try? confirmations.confirm(productID: product.id, catalogueID: record.catalogueID)) != nil else { return }
        identityConfirmations = confirmations
        try? identityConfirmations.save(to: identityConfirmationsURL)
        refreshEvidence()
    }

    func removeIdentityConfirmation(of product: NormalizedPluginProduct) {
        var confirmations = identityConfirmations
        confirmations.remove(productID: product.id)
        identityConfirmations = confirmations
        try? identityConfirmations.save(to: identityConfirmationsURL)
        refreshEvidence()
    }
}
