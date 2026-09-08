// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation

public struct BundleMetadataReader: Sendable {
    private let mac: MacArchitecture

    public init(mac: MacArchitecture = .current) { self.mac = mac }

    public func read(bundleURL: URL, format: PluginFormat) -> PluginBundleRecord {
        let plistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        let plist = SafeFileAccess.contained(plistURL, in: bundleURL) ? readPropertyList(at: plistURL) : nil
        let vst3Info = format == .vst3 ? readVST3ModuleInfo(bundleURL: bundleURL) : nil

        let bundleIdentifier = stringValue(plist?["CFBundleIdentifier"])
        let bundleName = stringValue(plist?["CFBundleDisplayName"])
            ?? stringValue(plist?["CFBundleName"])
        let moduleName = stringValue(vst3Info?["Name"])
        let name = moduleName
            ?? bundleName
            ?? DisplaySanitiser.sanitise(bundleURL.deletingPathExtension().lastPathComponent)
            ?? "Plugin"

        let moduleVendor = (vst3Info?["Factory Info"] as? [String: Any])
            .flatMap { stringValue($0["Vendor"]) }
        let vendorIsInferred = moduleVendor == nil && audioUnitVendor(from: plist) == nil
        let vendor = moduleVendor
            ?? audioUnitVendor(from: plist)
            ?? inferredVendor(from: bundleIdentifier)

        let displayVersion = stringValue(vst3Info?["Version"])
            ?? stringValue(plist?["CFBundleShortVersionString"])
        let buildVersion = stringValue(plist?["CFBundleVersion"])
        let executableURL = executableURL(bundleURL: bundleURL, plist: plist)
        let architectures = executableURL
            .map(MachOArchitectureDetector.architectures(at:))
            ?? []
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: bundleURL.path
        )
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        let modifiedAt = attributes?[.modificationDate] as? Date

        var identifiers: [PluginIdentifier] = []
        appendIdentifier(
            &identifiers,
            kind: .bundleIdentifier,
            value: bundleIdentifier
        )
        appendAudioUnitIdentifiers(
            &identifiers,
            plist: plist
        )
        appendVST3ClassIdentifiers(
            &identifiers,
            moduleInfo: vst3Info
        )

        var evidence: [VersionEvidence] = []
        appendEvidence(&evidence, kind: vendorIsInferred ? .inferred : .bundleInformation,
                       field: "Vendor", value: vendor)
        appendEvidence(
            &evidence,
            kind: .bundleInformation,
            field: "CFBundleShortVersionString",
            value: stringValue(plist?["CFBundleShortVersionString"])
        )
        appendEvidence(
            &evidence,
            kind: .bundleInformation,
            field: "CFBundleVersion",
            value: buildVersion
        )
        appendEvidence(
            &evidence,
            kind: .vst3ModuleInfo,
            field: "Version",
            value: stringValue(vst3Info?["Version"])
        )
        appendAudioUnitEvidence(&evidence, plist: plist)
        appendVST3ClassEvidence(&evidence, moduleInfo: vst3Info)
        for architecture in architectures {
            appendEvidence(
                &evidence,
                kind: .executable,
                field: "Architecture",
                value: architecture.rawValue
            )
        }

        var issues: [ScanIssue] = []
        if plist == nil {
            issues.append(
                ScanIssue(
                    id: "missing-info-plist",
                    severity: .warning,
                    title: "Bundle metadata is unavailable",
                    detail: "The plugin has no readable Info.plist, so its identity and version may be incomplete."
                )
            )
        }
        if displayVersion == nil && buildVersion == nil {
            issues.append(
                ScanIssue(
                    id: "missing-version",
                    severity: .warning,
                    title: "Installed version is unknown",
                    detail: "No readable release or build version was found in the plugin metadata."
                )
            )
        }
        if executableURL == nil {
            issues.append(
                ScanIssue(
                    id: "missing-executable",
                    severity: .critical,
                    title: "Plugin executable is missing",
                    detail: "The bundle metadata does not point to a readable plugin executable."
                )
            )
        } else if InstalledArchitecture.classify(architectures) == .unknown {
            issues.append(
                ScanIssue(
                    id: "unknown-architecture",
                    severity: .warning,
                    title: "Architecture could not be identified",
                    detail: "The plugin executable was found, but its Mach-O architecture could not be read."
                )
            )
        } else if architectures == [.i386] {
            issues.append(
                ScanIssue(
                    id: "32-bit-only",
                    severity: .critical,
                    title: "32-bit Intel plugin",
                    detail: "This plugin contains only a 32-bit Intel executable and cannot load in modern macOS hosts."
                )
            )
        } else if InstalledArchitecture.classify(architectures) == .intel64 && mac.processor == .appleSilicon {
            issues.append(
                ScanIssue(
                    id: "intel-only",
                    severity: .warning,
                    title: "Intel-only copy",
                    detail: "This Mac has Apple Silicon, but this file declares only Intel executable code. Review native version availability and the DAW's Rosetta requirements in product details."
                )
            )
        } else if InstalledArchitecture.classify(architectures) == .appleSilicon && mac.processor == .intel {
            issues.append(ScanIssue(id: "apple-silicon-only", severity: .critical,
                title: "Apple Silicon plugin on an Intel Mac",
                detail: "This file has no detected Intel executable. Rosetta cannot run Apple Silicon code on Intel. Look for an Intel or Universal installer from the vendor."))
        }

        return PluginBundleRecord(
            id: stableIdentifier(
                format: format,
                bundleIdentifier: bundleIdentifier,
                path: bundleURL
            ),
            name: name,
            vendor: vendor,
            format: format,
            bundleIdentifier: bundleIdentifier,
            displayVersion: displayVersion,
            buildVersion: buildVersion,
            path: bundleURL,
            executablePath: executableURL,
            architectures: architectures,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            identifiers: identifiers,
            evidence: evidence,
            issues: issues,
            declaredLinks: DeclaredProductLink.extract(plist: plist, moduleInfo: vst3Info)
        )
    }

    private func readPropertyList(at url: URL) -> [String: Any]? {
        guard
            let data = SafeFileAccess.data(at: url),
            let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        else {
            return nil
        }

        return object as? [String: Any]
    }

    private func readVST3ModuleInfo(bundleURL: URL) -> [String: Any]? {
        let candidates = [
            bundleURL.appendingPathComponent(
                "Contents/Resources/moduleinfo.json",
                isDirectory: false
            ),
            bundleURL.appendingPathComponent(
                "Contents/moduleinfo.json",
                isDirectory: false
            )
        ]

        for candidate in candidates {
            guard
                SafeFileAccess.contained(candidate, in: bundleURL),
                let data = SafeFileAccess.data(at: candidate),
                JSONDepth.isWithinLimit(data),
                let object = try? JSONSerialization.jsonObject(with: data),
                let dictionary = object as? [String: Any]
            else {
                continue
            }

            return dictionary
        }

        return nil
    }

    private func executableURL(
        bundleURL: URL,
        plist: [String: Any]?
    ) -> URL? {
        SafeFileAccess.executable(in: bundleURL, name: stringValue(plist?["CFBundleExecutable"]))
    }

    private func audioUnitVendor(from plist: [String: Any]?) -> String? {
        guard
            let components = plist?["AudioComponents"] as? [[String: Any]],
            let first = components.first,
            let name = stringValue(first["name"])
        else {
            return nil
        }

        let pieces = name.split(separator: ":", maxSplits: 1)
        guard pieces.count == 2 else {
            return nil
        }

        let vendor = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return vendor.isEmpty ? nil : vendor
    }

    private func appendAudioUnitIdentifiers(
        _ identifiers: inout [PluginIdentifier],
        plist: [String: Any]?
    ) {
        guard let components = plist?["AudioComponents"] as? [[String: Any]] else {
            return
        }

        // A plug-in declares a handful of components; hundreds signal a broken or hostile file.
        for component in components.prefix(maximumDeclaredEntries) {
            guard
                let manufacturer = stringValue(component["manufacturer"]),
                let type = stringValue(component["type"]),
                let subtype = stringValue(component["subtype"])
            else {
                continue
            }

            appendIdentifier(
                &identifiers,
                kind: .audioUnitComponent,
                value: "\(manufacturer):\(type):\(subtype)"
            )
        }
    }

    private func appendVST3ClassIdentifiers(
        _ identifiers: inout [PluginIdentifier],
        moduleInfo: [String: Any]?
    ) {
        guard let classes = moduleInfo?["Classes"] as? [[String: Any]] else {
            return
        }

        for pluginClass in classes.prefix(maximumDeclaredEntries) {
            // A VST3 edit controller is part of a plugin, not another audio product.
            // Retain unclassified entries conservatively; only exclude an explicit controller.
            guard stringValue(pluginClass["Category"]) != "Component Controller Class" else { continue }
            appendIdentifier(
                &identifiers,
                kind: .vst3Class,
                value: stringValue(pluginClass["CID"])
            )
        }
    }

    private func appendAudioUnitEvidence(
        _ evidence: inout [VersionEvidence],
        plist: [String: Any]?
    ) {
        guard let components = plist?["AudioComponents"] as? [[String: Any]] else {
            return
        }

        for (index, component) in components.prefix(maximumDeclaredEntries).enumerated() {
            appendEvidence(&evidence, kind: .audioComponent,
                field: "AudioComponents[\(index)].type", value: stringValue(component["type"]))
            appendEvidence(
                &evidence,
                kind: .audioComponent,
                field: "AudioComponents[\(index)].name",
                value: stringValue(component["name"])
            )
            appendEvidence(
                &evidence,
                kind: .audioComponent,
                field: "AudioComponents[\(index)].version",
                value: stringValue(component["version"])
            )
        }
    }

    private func appendVST3ClassEvidence(
        _ evidence: inout [VersionEvidence],
        moduleInfo: [String: Any]?
    ) {
        guard let classes = moduleInfo?["Classes"] as? [[String: Any]] else {
            return
        }

        for (index, pluginClass) in classes.prefix(maximumDeclaredEntries).enumerated() {
            if stringValue(pluginClass["Category"]) == "Audio Module Class" {
                let subcategories = (pluginClass["Sub Categories"] as? [String])?.joined(separator: "|")
                    ?? (pluginClass["Sub Categories"] as? String)
                appendEvidence(&evidence, kind: .vst3ModuleInfo,
                    field: "Classes[\(index)].Sub Categories", value: subcategories)
            }
            appendEvidence(
                &evidence,
                kind: .vst3ModuleInfo,
                field: "Classes[\(index)].CID",
                value: stringValue(pluginClass["CID"])
            )
            appendEvidence(
                &evidence,
                kind: .vst3ModuleInfo,
                field: "Classes[\(index)].Version",
                value: stringValue(pluginClass["Version"])
            )
        }
    }

    private func inferredVendor(from bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier else {
            return nil
        }

        let pieces = bundleIdentifier.split(separator: ".")
        guard pieces.count >= 3 else {
            return nil
        }

        return String(pieces[1])
    }

    /// Upper bound on declared AudioComponents / VST3 classes read from one bundle.
    private let maximumDeclaredEntries = 256

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return DisplaySanitiser.sanitise(string)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func appendEvidence(
        _ evidence: inout [VersionEvidence],
        kind: EvidenceKind,
        field: String,
        value: String?
    ) {
        guard let value else {
            return
        }

        evidence.append(
            VersionEvidence(kind: kind, field: field, value: value)
        )
    }

    private func appendIdentifier(
        _ identifiers: inout [PluginIdentifier],
        kind: PluginIdentifierKind,
        value: String?
    ) {
        guard let value else {
            return
        }

        let canonicalValue: String
        switch kind {
        case .bundleIdentifier, .clapPlugin, .signingTeam:
            canonicalValue = value.lowercased()
        case .audioUnitComponent:
            canonicalValue = value
        case .vst3Class:
            canonicalValue = value
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        }

        let identifier = PluginIdentifier(kind: kind, value: canonicalValue)
        if !identifiers.contains(identifier) {
            identifiers.append(identifier)
        }
    }

    private func stableIdentifier(
        format: PluginFormat,
        bundleIdentifier: String?,
        path: URL
    ) -> String {
        let identity = [
            format.rawValue,
            bundleIdentifier ?? "",
            path.standardizedFileURL.path
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

}
