// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation

public enum CleanupItemKind: String, Codable, Sendable {
    case pluginBundle = "Plugin file"
    case application = "Application"
    /// A Core Audio (HAL) or Core MIDI driver bundle. Kernel and system extensions are never items.
    case driverBundle = "Driver"
    case preferences = "Preferences"
    case cache = "Cache"
    case applicationSupport = "Application support"
    case savedState = "Saved application state"
}

public struct CleanupItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let path: URL
    public let kind: CleanupItemKind
    public let containsUserCreatedContent: Bool
    public let previewFingerprint: String?
    public let contentsFingerprint: String?

    public init(path: URL, kind: CleanupItemKind, containsUserCreatedContent: Bool = false, contentsFingerprint: String? = nil) {
        self.id = path.standardizedFileURL.path
        self.path = path
        self.kind = kind
        self.containsUserCreatedContent = containsUserCreatedContent
        self.previewFingerprint = CleanupSafety.fingerprint(at: path)
        self.contentsFingerprint = contentsFingerprint
    }
}

public struct CleanupPlan: Hashable, Codable, Sendable {
    public let displayName: String
    public let items: [CleanupItem]
    public let excludedUserContentDescription: String

    public init(displayName: String, items: [CleanupItem], excludedUserContentDescription: String) {
        self.displayName = displayName
        self.items = items
        self.excludedUserContentDescription = excludedUserContentDescription
    }
}

/// No guessed support files: even exact bundle-ID preferences can contain licences.
/// App bundles may contain bundled content. Their contents are part of the previewed bundle.
public struct CleanupPlanner: Sendable {
    public let safety: CleanupSafety

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                allowedRoots: [URL]? = nil) {
        safety = CleanupSafety(homeDirectory: homeDirectory, allowedRoots: allowedRoots)
    }

    public func plan(for product: NormalizedPluginProduct) -> CleanupPlan {
        makePlan(displayName: product.name, items: product.requiresVerification ? [] : product.bundles.map {
            CleanupItem(path: $0.path, kind: .pluginBundle)
        })
    }

    public func plan(for daw: InstalledDAWRecord) -> CleanupPlan {
        makePlan(displayName: daw.name, items: daw.identityIsInferred ? [] : [CleanupItem(path: daw.path, kind: .application)])
    }

    /// Driver removal is vendor-managed for the first release.
    public func plan(for driver: DriverRecord) -> CleanupPlan {
        CleanupPlan(displayName: driver.name, items: [],
            excludedUserContentDescription: Self.ineligibilityReason(driver) ?? "Use the manufacturer's removal instructions. Drivers may share services with other audio devices; this beta does not remove driver files.")
    }

    static func isRemovableKind(_ driver: DriverRecord) -> Bool {
        ineligibilityReason(driver) == nil
    }

    static func ineligibilityReason(_ driver: DriverRecord) -> String? {
        if (driver.bundleIdentifier ?? "").lowercased().hasPrefix("com.apple.") {
            return "This is part of macOS. Apple updates and removes it with the system; MK Studio Upkeep will not touch it."
        }
        let ext = driver.path.pathExtension.lowercased()
        if ext == "kext" || ext == "systemextension" {
            return "Kernel and system extensions cannot be removed by moving a file. Use the maker's uninstaller or System Settings › General › Login Items & Extensions; a restart is usually required."
        }
        guard ext == "driver" || ext == "plugin" else { return "This item is not a driver bundle MK Studio Upkeep can remove." }
        return nil
    }

    private func makePlan(displayName: String, items: [CleanupItem]) -> CleanupPlan {
        let allowed = items.filter { safety.validate($0) == nil }
        let unique = Dictionary(allowed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return CleanupPlan(displayName: displayName, items: unique.values.sorted { $0.id < $1.id },
            excludedUserContentDescription: "Only the listed software bundles, including their contents, are eligible. External projects, presets, samples, libraries, licences, preferences, support folders and drivers are preserved. Use the vendor's instructions for a full uninstall. Back up any custom content saved inside a bundle.")
    }
}

public struct CleanupSafety: Sendable {
    public let allowedRoots: [URL]
    /// Resolved paths of bundles that must not be moved right now, for example running applications.
    public let protectedPaths: Set<String>

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                allowedRoots: [URL]? = nil, protectedPaths: Set<String> = []) {
        self.protectedPaths = protectedPaths
        self.allowedRoots = (allowedRoots ?? [
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins"),
            homeDirectory.appendingPathComponent("Library/Audio/Plug-Ins"),
            URL(fileURLWithPath: "/Library/Audio/MIDI Drivers"),
            homeDirectory.appendingPathComponent("Library/Audio/MIDI Drivers"),
            URL(fileURLWithPath: "/Applications"),
            homeDirectory.appendingPathComponent("Applications")
        ]).map { $0.resolvingSymlinksInPath().standardizedFileURL }
    }

    /// Rechecked immediately before each move; changes invalidate the old preview.
    public func validate(_ item: CleanupItem) -> String? {
        guard !item.containsUserCreatedContent,
              item.kind == .pluginBundle || item.kind == .application || item.kind == .driverBundle else {
            return "This item is protected. Use the vendor's uninstall instructions."
        }
        let path = item.path.standardizedFileURL
        if protectedPaths.contains(path.resolvingSymlinksInPath().path) {
            return "Quit the application before uninstalling it."
        }
        let extensions: [String]
        switch item.kind {
        case .application: extensions = ["app"]
        case .driverBundle: extensions = ["driver", "plugin"]
        default: extensions = ["component", "vst3", "vst", "clap"]
        }
        if item.kind == .driverBundle {
            // A driver bundle must sit directly in a HAL or MIDI Drivers folder; nothing under /Library/Extensions.
            let parent = path.deletingLastPathComponent().pathComponents
            guard Array(parent.suffix(3)) == ["Audio", "Plug-Ins", "HAL"] || Array(parent.suffix(2)) == ["Audio", "MIDI Drivers"] else {
                return "Drivers can only be removed from the Core Audio HAL or MIDI Drivers folders."
            }
        }
        guard path.isFileURL, extensions.contains(path.pathExtension.lowercased()),
              path.path == path.resolvingSymlinksInPath().path,
              let root = allowedRoots.first(where: { path.path.hasPrefix($0.path + "/") }),
              (try? path.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            return "The item is outside approved locations, is a link, or is not a software bundle."
        }
        var parent = path.deletingLastPathComponent()
        while parent.path != root.path {
            if ["app", "component", "vst3", "vst", "clap", "kext", "systemextension", "driver", "plugin"].contains(parent.pathExtension.lowercased()) {
                return "Nested software bundles must be managed by their owning product."
            }
            parent.deleteLastPathComponent()
        }
        // Never move anything that belongs to macOS, whatever the caller planned.
        if path.path.hasPrefix("/System/") || path.path.hasPrefix("/Library/Extensions/") || path.path.hasPrefix("/Library/SystemExtensions/") {
            return "Don’t delete this: it is part of macOS or a system extension."
        }
        if let data = SafeFileAccess.data(at: path.appendingPathComponent("Contents/Info.plist")),
           let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
           (plist["CFBundleIdentifier"] as? String)?.lowercased().hasPrefix("com.apple.") == true {
            return "Don’t delete this: it is an Apple component installed with macOS."
        }
        guard let expected = item.previewFingerprint,
              Self.fingerprint(at: path) == expected else {
            return "This item changed after the preview. Rescan and review a new uninstall plan."
        }
        if let expected = item.contentsFingerprint,
           (try? BundleContentsPreview.scan(path).fingerprint) != expected {
            return "Bundle contents changed or cannot be rechecked. Review a new uninstall plan."
        }
        return nil
    }

    static func fingerprint(at url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let inode = attributes[.systemFileNumber], let device = attributes[.systemNumber] else { return nil }
        let metadata = url.appendingPathComponent("Contents/Info.plist")
        guard SafeFileAccess.contained(metadata, in: url), let data = SafeFileAccess.data(at: metadata) else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(device):\(inode):\(attributes[.creationDate] ?? ""): \(attributes[.modificationDate] ?? ""):\(hash)"
    }
}

public struct CleanupExecutionResult: Sendable {
    public let movedCount: Int
    public let failures: [String]
}

public enum CleanupExecutor {
    public static func execute(_ plan: CleanupPlan, safety: CleanupSafety = CleanupSafety(),
                               moveToTrash: (URL) throws -> Void) -> CleanupExecutionResult {
        // Validate the entire plan first to avoid a predictable partial uninstall.
        let invalid = plan.items.compactMap { item in
            safety.validate(item).map { "\(item.path.lastPathComponent): \($0)" }
        }
        guard invalid.isEmpty else { return CleanupExecutionResult(movedCount: 0, failures: invalid) }
        var failures: [String] = []
        var count = 0
        for item in plan.items {
            if let reason = safety.validate(item) {
                failures.append("\(item.path.lastPathComponent): \(reason)")
                break
            }
            do { try moveToTrash(item.path.standardizedFileURL); count += 1 }
            catch { failures.append("\(item.path.lastPathComponent): \(error.localizedDescription)"); break }
        }
        return CleanupExecutionResult(movedCount: count, failures: failures)
    }
}
