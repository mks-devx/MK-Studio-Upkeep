// SPDX-License-Identifier: BUSL-1.1
import CryptoKit
import Foundation

public enum ProductMatchConfidence: Int, Codable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (
        lhs: ProductMatchConfidence,
        rhs: ProductMatchConfidence
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ProductMatchReason: String, Codable, Sendable {
    case singleBundle = "Single bundle"
    case sharedIdentifier = "Shared identifier"
    case vendorAndProductName = "Vendor and product name"
    case missingVendorInferred = "Missing vendor inferred"
    case multiComponentContainer = "Multi-component container"
}

public struct ProductMatchEvidence: Hashable, Codable, Sendable {
    public let reason: ProductMatchReason
    public let detail: String

    public init(reason: ProductMatchReason, detail: String) {
        self.reason = reason
        self.detail = detail
    }
}

public struct NormalizedPluginProduct: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let vendor: String?
    public let bundles: [PluginBundleRecord]
    public let confidence: ProductMatchConfidence
    public let matchEvidence: [ProductMatchEvidence]
    public let requiresVerification: Bool

    public init(
        id: String,
        name: String,
        vendor: String?,
        bundles: [PluginBundleRecord],
        confidence: ProductMatchConfidence,
        matchEvidence: [ProductMatchEvidence],
        requiresVerification: Bool
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.bundles = bundles
        self.confidence = confidence
        self.matchEvidence = matchEvidence
        self.requiresVerification = requiresVerification
    }

    public var formats: Set<PluginFormat> {
        Set(bundles.map(\.format))
    }

    public var architectures: Set<BinaryArchitecture> {
        Set(bundles.flatMap(\.architectures))
    }

    public var installedVersions: Set<String> {
        Set(
            bundles.compactMap {
                $0.displayVersion ?? $0.buildVersion
            }
        )
    }

    public var hasVersionDivergence: Bool {
        installedVersions.count > 1
    }

    public var issues: [ScanIssue] {
        Array(Set(bundles.flatMap(\.issues))).sorted {
            if $0.severity != $1.severity {
                return $0.severity > $1.severity
            }
            return $0.title.localizedStandardCompare($1.title)
                == .orderedAscending
        }
    }
}

public struct ProductNormalizationReport: Hashable, Codable, Sendable {
    public let products: [NormalizedPluginProduct]
    public let inputBundleCount: Int

    public init(
        products: [NormalizedPluginProduct],
        inputBundleCount: Int
    ) {
        self.products = products
        self.inputBundleCount = inputBundleCount
    }

    public var groupedProductCount: Int {
        products.count
    }

    public var verificationProductCount: Int {
        products.filter { $0.requiresVerification }.count
    }
}

public struct ProductNormalizer: Sendable {
    private struct Candidate: Sendable {
        let record: PluginBundleRecord
        let nameKey: String
        let vendorKey: String?
        let vendorDisplayName: String?
        let bundleRoot: String?
        let isMultiComponentContainer: Bool
    }

    private struct WorkingGroup {
        let key: String
        var candidates: [Candidate]
        var inferredMissingVendorRecordIDs: Set<String>
    }

    public init() {}

    public func normalize(
        records: [PluginBundleRecord]
    ) -> ProductNormalizationReport {
        // Preserve the synchronous API for clients; scans use the throwing entry point.
        try! normalizeImpl(records: records, checkCancellation: {})
    }

    public func normalizeCancellable(records: [PluginBundleRecord]) throws -> ProductNormalizationReport {
        try normalizeImpl(records: records, checkCancellation: { try Task.checkCancellation() })
    }

    private func normalizeImpl(records: [PluginBundleRecord], checkCancellation: () throws -> Void) throws -> ProductNormalizationReport {
        let candidates = try records.map { record in
            try checkCancellation()
            return makeCandidate(record)
        }
        let knownVendorCandidates = candidates.filter { $0.vendorKey != nil }
        let missingVendorCandidates = candidates.filter { $0.vendorKey == nil }

        var groups: [String: WorkingGroup] = [:]
        var groupKeysByName: [String: Set<String>] = [:]
        for candidate in knownVendorCandidates {
            try checkCancellation()
            guard let vendorKey = candidate.vendorKey else {
                continue
            }
            let key = "named:\(vendorKey):\(candidate.nameKey)"
            groupKeysByName[candidate.nameKey, default: []].insert(key)
            if groups[key] == nil {
                groups[key] = WorkingGroup(
                    key: key,
                    candidates: [],
                    inferredMissingVendorRecordIDs: []
                )
            }
            groups[key]?.candidates.append(candidate)
        }

        for candidate in missingVendorCandidates {
            try checkCancellation()
            let compatibleKeys = (groupKeysByName[candidate.nameKey] ?? [])
                .filter { key in
                    guard let group = groups[key] else { return false }
                    return canInferMissingVendor(candidate, from: group.candidates)
                }.sorted()

            if compatibleKeys.count == 1, let key = compatibleKeys.first {
                groups[key]?.candidates.append(candidate)
                groups[key]?.inferredMissingVendorRecordIDs.insert(
                    candidate.record.id
                )
                continue
            }

            let unknownKey: String
            if let bundleRoot = candidate.bundleRoot {
                unknownKey = "unknown:\(candidate.nameKey):\(bundleRoot)"
            } else {
                unknownKey = "record:\(candidate.record.id)"
            }

            groupKeysByName[candidate.nameKey, default: []].insert(unknownKey)
            if groups[unknownKey] == nil {
                groups[unknownKey] = WorkingGroup(
                    key: unknownKey,
                    candidates: [],
                    inferredMissingVendorRecordIDs: []
                )
            }
            groups[unknownKey]?.candidates.append(candidate)
        }

        let products = try groups.values
            .map { group in try checkCancellation(); return makeProduct(group) }
            .sorted {
                let vendorComparison = ($0.vendor ?? "")
                    .localizedStandardCompare($1.vendor ?? "")
                if vendorComparison != .orderedSame {
                    return vendorComparison == .orderedAscending
                }

                let nameComparison = $0.name.localizedStandardCompare($1.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return $0.id < $1.id
            }

        return ProductNormalizationReport(
            products: products,
            inputBundleCount: records.count
        )
    }

    private func makeCandidate(_ record: PluginBundleRecord) -> Candidate {
        let vendor = canonicalVendor(record.vendor)
        return Candidate(
            record: record,
            nameKey: canonicalName(record.name),
            vendorKey: vendor?.key,
            vendorDisplayName: vendor?.displayName,
            bundleRoot: canonicalBundleRoot(record.bundleIdentifier),
            isMultiComponentContainer: isMultiComponentContainer(record)
        )
    }

    private func makeProduct(_ group: WorkingGroup) -> NormalizedPluginProduct {
        let candidates = group.candidates.sorted {
            if $0.record.format != $1.record.format {
                return $0.record.format.rawValue < $1.record.format.rawValue
            }
            return $0.record.path.path.localizedStandardCompare(
                $1.record.path.path
            ) == .orderedAscending
        }
        let records = candidates.map(\.record)
        let name = preferredDisplayValue(records.map(\.name))
        let vendorValues = candidates.compactMap(\.vendorDisplayName)
        let vendor = vendorValues.isEmpty
            ? nil
            : preferredDisplayValue(vendorValues)
        let hasContainer = candidates.contains {
            $0.isMultiComponentContainer
        }
        let inferredMissingVendor = !group.inferredMissingVendorRecordIDs.isEmpty
        let sharedIdentifier = hasSharedIdentifier(records)

        var matchEvidence: [ProductMatchEvidence] = []
        if records.count == 1 {
            matchEvidence.append(
                ProductMatchEvidence(
                    reason: .singleBundle,
                    detail: "The product currently contains one \(records[0].format.rawValue) bundle."
                )
            )
        } else if sharedIdentifier {
            matchEvidence.append(
                ProductMatchEvidence(
                    reason: .sharedIdentifier,
                    detail: "Bundles share at least one stable format or bundle identifier."
                )
            )
        } else {
            matchEvidence.append(
                ProductMatchEvidence(
                    reason: .vendorAndProductName,
                    detail: "Bundles share the normalized vendor and product name."
                )
            )
        }

        if inferredMissingVendor {
            matchEvidence.append(
                ProductMatchEvidence(
                    reason: .missingVendorInferred,
                    detail: "A bundle without vendor metadata was attached to the only compatible named product."
                )
            )
        }

        if hasContainer {
            matchEvidence.append(
                ProductMatchEvidence(
                    reason: .multiComponentContainer,
                    detail: "At least one bundle exposes multiple plugin components and may represent more than one commercial product."
                )
            )
        }

        let confidence: ProductMatchConfidence
        if hasContainer || inferredMissingVendor {
            confidence = .low
        } else if sharedIdentifier {
            confidence = .high
        } else if vendor != nil {
            confidence = .medium
        } else {
            confidence = .low
        }

        let stableSource: String
        if let sharedValue = sharedIdentifierValue(records) {
            // Some vendors reuse an identifier across distinct named products.
            // Include the normalization group so separate rows cannot collide.
            stableSource = "identifier:\(sharedValue):\(group.key)"
        } else if let vendor {
            stableSource = "name:\(canonicalVendor(vendor)?.key ?? vendor):\(canonicalName(name))"
        } else {
            stableSource = "group:\(group.key)"
        }

        return NormalizedPluginProduct(
            id: stableHash(stableSource),
            name: name,
            vendor: vendor,
            bundles: records,
            confidence: confidence,
            matchEvidence: matchEvidence,
            requiresVerification: confidence == .low || hasContainer
        )
    }

    private func canInferMissingVendor(
        _ candidate: Candidate,
        from possibleMatches: [Candidate]
    ) -> Bool {
        let matchingRoot = candidate.bundleRoot.map { root in
            possibleMatches.contains { $0.bundleRoot == root }
        } ?? false
        if matchingRoot {
            return true
        }

        let candidateVersion = candidate.record.displayVersion
            ?? candidate.record.buildVersion
        guard let candidateVersion else {
            return false
        }

        return possibleMatches.contains { possibleMatch in
            guard
                let matchVersion = possibleMatch.record.displayVersion
                    ?? possibleMatch.record.buildVersion
            else {
                return false
            }
            return VersionComparator.compare(candidateVersion, matchVersion)
                == .equal
        }
    }

    private func isMultiComponentContainer(
        _ record: PluginBundleRecord
    ) -> Bool {
        let relevantKind: PluginIdentifierKind?
        switch record.format {
        case .audioUnit:
            relevantKind = .audioUnitComponent
        case .vst3:
            relevantKind = .vst3Class
        case .vst2, .clap:
            relevantKind = nil
        }

        guard let relevantKind else {
            return false
        }

        return record.identifiers.filter { $0.kind == relevantKind }.count > 1
    }

    private func hasSharedIdentifier(
        _ records: [PluginBundleRecord]
    ) -> Bool {
        sharedIdentifierValue(records) != nil
    }

    private func sharedIdentifierValue(
        _ records: [PluginBundleRecord]
    ) -> String? {
        guard records.count > 1 else {
            return nil
        }

        var counts: [PluginIdentifier: Int] = [:]
        for record in records {
            for identifier in Set(record.identifiers) {
                counts[identifier, default: 0] += 1
            }
        }

        return counts
            .filter { $0.value == records.count }
            .map { "\($0.key.kind.rawValue):\($0.key.value)" }
            .sorted()
            .first
    }

    private func canonicalName(_ value: String) -> String {
        let folded = value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .replacingOccurrences(of: "_", with: " ")
        var tokens = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let formatSuffixes: Set<String> = [
            "au", "aax", "clap", "component", "vst", "vst2", "vst3"
        ]
        if let last = tokens.last, formatSuffixes.contains(last) {
            tokens.removeLast()
        }

        return tokens.joined(separator: " ")
    }

    private func canonicalVendor(
        _ value: String?
    ) -> (key: String, displayName: String)? {
        guard let value else {
            return nil
        }

        let folded = value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "-", with: " ")
        var tokens = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let corporateSuffixes: Set<String> = [
            "ag", "corp", "corporation", "gmbh", "inc", "incorporated",
            "limited", "llc", "ltd", "software"
        ]
        while let last = tokens.last, corporateSuffixes.contains(last) {
            tokens.removeLast()
        }

        guard !tokens.isEmpty else {
            return nil
        }

        let key = tokens.joined(separator: " ")
        if key == "tokyodawnlabs" || key == "tokyo dawn labs" {
            return ("tokyo dawn labs", "Tokyo Dawn Labs")
        }
        // Reviewed AU vendor labels and bundle-identifier-derived VST labels.
        // Keep these exact: substring matching could merge unrelated vendors.
        if ["d16group", "d16 group", "d16 group audio"].contains(key) {
            return ("d16 group", "D16 Group")
        }
        if ["toguaudioline", "tal togu audio line", "togu audio line"].contains(key) {
            return ("togu audio line", "TAL-Togu Audio Line")
        }
        if ["valhalladsp", "valhalla dsp"].contains(key) {
            return ("valhalla dsp", "Valhalla DSP")
        }
        let aliases: [String: String] = [
            "fabfilter": "FabFilter",
            "izotope": "iZotope",
            "native instruments": "Native Instruments"
        ]
        let displayName = aliases[key]
            ?? value.trimmingCharacters(in: .whitespacesAndNewlines)

        return (key, displayName)
    }

    private func canonicalBundleRoot(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        var components = value
            .lowercased()
            .split(separator: ".")
            .map(String.init)
        let suffixes: Set<String> = [
            "audiounit", "component", "effect", "instrument",
            "musicdevice", "musiceffect", "vst", "vst2", "vst3"
        ]
        while let last = components.last, suffixes.contains(last) {
            components.removeLast()
        }

        let result = components.joined(separator: ".")
        return result.isEmpty ? nil : result
    }

    private func preferredDisplayValue(_ values: [String]) -> String {
        let counts = Dictionary(grouping: values, by: { $0 })
            .mapValues(\.count)
        return counts
            .sorted {
                if $0.value != $1.value {
                    return $0.value > $1.value
                }
                return $0.key.localizedStandardCompare($1.key)
                    == .orderedAscending
            }
            .first?
            .key
            ?? "Unknown product"
    }

    private func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map {
            String(format: "%02x", $0)
        }.joined()
    }
}
