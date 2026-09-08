// SPDX-License-Identifier: BUSL-1.1
import Foundation
import Security

/// Who made a bundle, read from the bundle itself: the code signature's signer (verified
/// against Apple's certificate chain) and the copyright line. Works for any bundle on any
/// Mac without a curated table, so unknown items can still be described honestly.
public struct BundleProvenance: Hashable, Codable, Sendable {
    public enum Signature: String, Codable, Sendable {
        case apple = "Apple"
        case developerID = "Developer ID"
        case macAppStore = "Mac App Store"
        case adHoc = "Ad hoc (no identity)"
        case invalid = "Invalid signature"
        case unsigned = "Unsigned"
        /// Required metadata or executable could not be inspected safely; signature validation was skipped.
        case notVerified = "Not verified"
    }

    /// Static validation hashes the whole main executable; larger files are not checked.
    public static let maximumExecutableBytes = 1_073_741_824
    public let signature: Signature
    /// Organisation named in the signing certificate, for example "Example Audio Ltd".
    public let signer: String?
    public let teamIdentifier: String?
    public let copyright: String?

    public init(signature: Signature, signer: String?, teamIdentifier: String?, copyright: String?) {
        self.signature = signature; self.signer = signer; self.teamIdentifier = teamIdentifier; self.copyright = copyright
    }

    /// One line for a user: "Signed by Example Audio Ltd · © 2026 Example Audio Ltd"
    public var summary: String {
        var parts: [String] = []
        switch signature {
        case .apple: parts.append("Signed by Apple")
        case .developerID, .macAppStore: parts.append(signer.map { "Signed by \($0)" } ?? "Signed with a Developer ID")
        case .adHoc: parts.append("Signed without an identity")
        case .invalid: parts.append("Signature does not verify")
        case .unsigned: parts.append("Not signed")
        case .notVerified: parts.append("Signature not checked")
        }
        if let copyright, !copyright.isEmpty { parts.append(copyright) }
        return parts.joined(separator: " · ")
    }

    /// Reads signature and copyright. Never executes the bundle; only metadata is inspected.
    public static func read(at url: URL) -> BundleProvenance {
        let copyright = readCopyright(at: url)
        // Security's static-code APIs open the main executable themselves and block on anything that
        // is not an ordinary file (a FIFO never returns). If the bundle declares an executable that
        // exists, it must be an ordinary file of bounded size before Security is asked about it.
        if executableIsUnsafeToOpen(at: url) {
            return BundleProvenance(signature: .notVerified, signer: nil, teamIdentifier: nil, copyright: copyright)
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else {
            return BundleProvenance(signature: .unsigned, signer: nil, teamIdentifier: nil, copyright: copyright)
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess else {
            return BundleProvenance(signature: .notVerified, signer: nil, teamIdentifier: nil, copyright: copyright)
        }
        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement)
        if validity == errSecCSUnsigned { return BundleProvenance(signature: .unsigned, signer: nil, teamIdentifier: nil, copyright: copyright) }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else {
            return BundleProvenance(signature: validity == errSecSuccess ? .adHoc : .invalid, signer: nil, teamIdentifier: nil, copyright: copyright)
        }
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let leaf = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        let signatureFlags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if SecCodeSignatureFlags(rawValue: signatureFlags).contains(.adhoc) {
            // An ad-hoc signature cannot satisfy an Apple certificate requirement. Check
            // its integrity separately, while never presenting it as a verified publisher.
            let integrity = SecStaticCodeCheckValidity(code,
                SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil)
            return BundleProvenance(signature: integrity == errSecSuccess ? .adHoc : .invalid,
                signer: nil, teamIdentifier: nil, copyright: copyright)
        }
        guard validity == errSecSuccess else {
            return BundleProvenance(signature: .invalid, signer: leaf.flatMap(organisation), teamIdentifier: team, copyright: copyright)
        }
        guard let leaf else { return BundleProvenance(signature: .adHoc, signer: nil, teamIdentifier: nil, copyright: copyright) }
        return BundleProvenance(signature: classify(leaf), signer: organisation(from: leaf), teamIdentifier: team, copyright: copyright)
    }

    /// True when metadata cannot be safely inspected, or its executable is not an ordinary
    /// bounded file inside the bundle. Security must not reopen metadata this reader rejected.
    /// A bundle with no executable at all is left to Security, which reports it as unsigned.
    static func executableIsUnsafeToOpen(at url: URL) -> Bool {
        guard url.isFileURL else { return true }
        var rootStatus = stat()
        guard lstat(url.path, &rootStatus) == 0 else { return true }
        // The provenance reader also supports standalone Mach-O tools.
        if (rootStatus.st_mode & S_IFMT) == S_IFREG {
            return rootStatus.st_size < 0 || rootStatus.st_size > maximumExecutableBytes
        }
        guard (rootStatus.st_mode & S_IFMT) == S_IFDIR else { return true }
        let resources = url.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        guard SafeFileAccess.contained(resources, in: url) else { return true }
        var resourceStatus = stat()
        if lstat(resources.path, &resourceStatus) == 0 {
            guard SafeFileAccess.data(at: resources) != nil else { return true }
        } else if errno != ENOENT { return true }
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard SafeFileAccess.contained(info, in: url), let data = SafeFileAccess.data(at: info),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return true }
        // Security falls back to the bundle filename when this field is missing or malformed.
        let declaredName = plist["CFBundleExecutable"] as? String
        let name = declaredName.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        guard name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { return true }
        let candidate = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
        var status = stat()
        guard lstat(candidate.path, &status) == 0 else { return false }  // nothing to open
        guard (status.st_mode & S_IFMT) == S_IFREG, SafeFileAccess.executable(in: url, name: name) != nil else { return true }
        return status.st_size > maximumExecutableBytes
    }

    static func readCopyright(at url: URL) -> String? {
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard SafeFileAccess.contained(info, in: url), let data = SafeFileAccess.data(at: info),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return nil }
        let value = (plist["NSHumanReadableCopyright"] as? String) ?? (plist["CFBundleGetInfoString"] as? String)
        return value.flatMap { DisplaySanitiser.sanitise($0, maximumLength: 200) }
    }

    /// "Developer ID Application: Example Audio Ltd (ABCDEFGH12)" → the organisation.
    static func organisation(from subjectSummary: String) -> String? {
        var value = subjectSummary
        for prefix in ["Developer ID Application: ", "Apple Distribution: ", "Apple Development: ", "3rd Party Mac Developer Application: ", "Mac Developer: "] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if let range = value.range(of: #"\s*\([A-Z0-9]{10}\)$"#, options: .regularExpression) { value.removeSubrange(range) }
        value = value.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    static func classify(_ subjectSummary: String) -> Signature {
        if subjectSummary == "Software Signing" { return .apple }
        if subjectSummary.hasPrefix("Apple Mac OS Application Signing") || subjectSummary.hasPrefix("Apple Distribution") { return .macAppStore }
        if subjectSummary.hasPrefix("Developer ID Application") || subjectSummary.hasPrefix("3rd Party Mac Developer Application") { return .developerID }
        return .adHoc
    }
}
