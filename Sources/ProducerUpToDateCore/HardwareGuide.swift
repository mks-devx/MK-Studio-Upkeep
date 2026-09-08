// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Plain explanations and official update routes for detected hardware and drivers.
/// Every entry is a reviewed navigation aid: it says who makes something and where its
/// updates come from. It never claims a firmware or driver version is current.
public struct HardwareVendorGuide: Hashable, Sendable {
    public let vendor: String
    /// Where updates come from, in the user's words: "Antelope Launcher", "macOS updates".
    public let updateRoute: String
    public let url: URL?
    /// A manager application that delivers the updates, when the vendor has one.
    public let managerBundleIdentifier: String?
    public let note: String?
    /// Display name of the vendor app, also used to find it by name in the Applications
    /// folders when its bundle identifier is unknown or differs between versions.
    public var managerAppName: String? {
        switch vendor {
        case "Antelope Audio": "Antelope Launcher"
        case "Native Instruments": "Native Access"
        case "Ableton": "Ableton Live"
        case "Focusrite": "Focusrite Control 2"
        case "Universal Audio": "UA Connect"
        case "PreSonus": "Universal Control"
        case "Apogee": "Apogee Control 2"
        case "Arturia": "Arturia Software Center"
        case "Novation": "Novation Components"
        case "Steinberg and Yamaha": "Steinberg Download Assistant"
        case "Solid State Logic": "SSL 360"
        case "Elektron": "Elektron Transfer"
        case "RØDE": "RØDE Central"
        case "Shure": "ShurePlus MOTIV"
        case "Softube": "Softube Central"
        case "IK Multimedia": "IK Product Manager"
        case "KORG": "KORG Software Pass"
        default: nil
        }
    }

    static let entries: [(names: [String], prefixes: [String], guide: HardwareVendorGuide)] = [
        (["apple inc.", "apple"], ["com.apple."],
         .init(vendor: "Apple", updateRoute: "macOS updates", url: URL(string: "https://support.apple.com/macos"), managerBundleIdentifier: nil,
               note: "Built-in audio and Apple's own audio components are updated together with macOS. They are not third-party drivers.")),
        (["antelope audio", "antelope"], ["com.antelopeaudio."],
         .init(vendor: "Antelope Audio", updateRoute: "Antelope Launcher", url: URL(string: "https://support.antelopeaudio.com/en/support/solutions/articles/42000111514-downloads"), managerBundleIdentifier: nil,
               note: "Antelope Launcher installs firmware and the Unified Driver for Orion, Zen, Discrete and Galaxy interfaces.")),
        (["native instruments", "native instruments gmbh"], ["com.native-instruments."],
         .init(vendor: "Native Instruments", updateRoute: "Native Access", url: URL(string: "https://www.native-instruments.com/en/support/downloads/"), managerBundleIdentifier: nil,
               note: "Native Access delivers drivers and software; Maschine and Komplete Kontrol hardware firmware is updated from within their applications.")),
        (["ableton", "ableton ag"], ["com.ableton."],
         .init(vendor: "Ableton", updateRoute: "Ableton Live", url: URL(string: "https://www.ableton.com/en/push/"), managerBundleIdentifier: nil,
               note: "Push firmware is updated by Ableton Live when the controller is connected.")),
        (["focusrite", "focusrite audio engineering"], ["com.focusrite."],
         .init(vendor: "Focusrite", updateRoute: "Focusrite Control 2 and the downloads page", url: URL(string: "https://downloads.focusrite.com"), managerBundleIdentifier: nil, note: nil)),
        (["universal audio", "universal audio inc."], ["com.uaudio."],
         .init(vendor: "Universal Audio", updateRoute: "UA Connect", url: URL(string: "https://www.uaudio.com/support/downloads.html"), managerBundleIdentifier: nil, note: nil)),
        (["rme", "rme audio"], ["de.rme-audio.", "com.rme."],
         .init(vendor: "RME", updateRoute: "RME downloads page", url: URL(string: "https://www.rme-audio.de/downloads.html"), managerBundleIdentifier: nil, note: nil)),
        (["motu", "mark of the unicorn"], ["com.motu."],
         .init(vendor: "MOTU", updateRoute: "MOTU downloads page", url: URL(string: "https://motu.com/download"), managerBundleIdentifier: nil, note: nil)),
        (["presonus", "presonus audio electronics"], ["com.presonus."],
         .init(vendor: "PreSonus", updateRoute: "Universal Control", url: URL(string: "https://www.presonus.com/pages/downloads"), managerBundleIdentifier: nil, note: nil)),
        (["apogee", "apogee electronics"], ["com.apogee.", "com.apogeedigital."],
         .init(vendor: "Apogee", updateRoute: "Apogee Control and the support page", url: URL(string: "https://apogeedigital.com/support"), managerBundleIdentifier: nil, note: nil)),
        (["arturia"], ["com.arturia."],
         .init(vendor: "Arturia", updateRoute: "Arturia Software Center and MIDI Control Center", url: URL(string: "https://www.arturia.com/support/downloads-manuals"), managerBundleIdentifier: nil,
               note: "Arturia Software Center updates interfaces and software; MIDI Control Center updates keyboard and controller firmware.")),
        (["novation", "focusrite-novation"], ["com.novation.", "com.focusrite.novation."],
         .init(vendor: "Novation", updateRoute: "Novation Components", url: URL(string: "https://components.novationmusic.com"), managerBundleIdentifier: nil, note: nil)),
        (["akai", "akai professional", "inmusic"], ["com.akaipro.", "com.inmusic."],
         .init(vendor: "Akai Professional", updateRoute: "Akai downloads page", url: URL(string: "https://www.akaipro.com/downloads"), managerBundleIdentifier: nil, note: nil)),
        (["roland", "roland corporation"], ["com.roland.", "jp.co.roland."],
         .init(vendor: "Roland", updateRoute: "Roland support page", url: URL(string: "https://www.roland.com/global/support/"), managerBundleIdentifier: nil, note: nil)),
        (["steinberg", "steinberg media technologies", "yamaha", "yamaha corporation"], ["com.steinberg.", "com.yamaha."],
         .init(vendor: "Steinberg and Yamaha", updateRoute: "Steinberg Download Assistant", url: URL(string: "https://www.steinberg.net/support/downloads/"), managerBundleIdentifier: nil, note: nil)),
        (["audient"], ["com.audient."],
         .init(vendor: "Audient", updateRoute: "Audient downloads page", url: URL(string: "https://audient.com/support/downloads/"), managerBundleIdentifier: nil, note: nil)),
        (["solid state logic", "ssl"], ["com.solidstatelogic."],
         .init(vendor: "Solid State Logic", updateRoute: "SSL 360 and the support page", url: URL(string: "https://www.solidstatelogic.com/support"), managerBundleIdentifier: nil, note: nil)),
        (["elektron", "elektron music machines"], ["se.elektron."],
         .init(vendor: "Elektron", updateRoute: "Elektron Transfer", url: URL(string: "https://www.elektron.se/support"), managerBundleIdentifier: nil, note: "Transfer updates instrument firmware; Overbridge provides the audio driver.")),
        (["korg", "korg inc."], ["jp.co.korg.", "com.korg."],
         .init(vendor: "KORG", updateRoute: "KORG downloads page", url: URL(string: "https://www.korg.com/us/support/download/"), managerBundleIdentifier: nil, note: nil)),
        (["m-audio"], ["com.m-audio."],
         .init(vendor: "M-Audio", updateRoute: "M-Audio support page", url: URL(string: "https://m-audio.com/support"), managerBundleIdentifier: nil, note: nil)),
        (["ik multimedia"], ["com.ikmultimedia."],
         .init(vendor: "IK Multimedia", updateRoute: "IK Product Manager", url: URL(string: "https://www.ikmultimedia.com/products/productmanager/"), managerBundleIdentifier: nil, note: nil)),
        (["behringer", "music tribe"], ["com.behringer.", "com.musictribe."],
         .init(vendor: "Behringer", updateRoute: "Behringer product page", url: URL(string: "https://www.behringer.com/downloads.html"), managerBundleIdentifier: nil, note: nil)),
        (["zoom", "zoom corporation"], ["jp.co.zoom."],
         .init(vendor: "Zoom", updateRoute: "Zoom support page", url: URL(string: "https://zoomcorp.com/en/us/support/"), managerBundleIdentifier: nil, note: nil)),
        (["tascam", "teac"], ["com.tascam.", "jp.co.teac."],
         .init(vendor: "TASCAM", updateRoute: "TASCAM downloads page", url: URL(string: "https://tascam.com/us/support"), managerBundleIdentifier: nil, note: nil)),
        (["rogue amoeba", "rogue amoeba software"], ["com.rogueamoeba."],
         .init(vendor: "Rogue Amoeba", updateRoute: "Audio Hijack, Loopback or SoundSource", url: URL(string: "https://rogueamoeba.com/support/"), managerBundleIdentifier: nil,
               note: "ACE, the Audio Capture Engine, is installed by Rogue Amoeba's apps to capture and route audio. Those apps update it.")),
        (["existential audio"], ["audio.existential."],
         .init(vendor: "Existential Audio", updateRoute: "BlackHole releases on GitHub", url: URL(string: "https://github.com/ExistentialAudio/BlackHole/releases"), managerBundleIdentifier: nil,
               note: "BlackHole is a free virtual audio driver for routing audio between apps.")),
        (["rode", "røde", "rode microphones", "røde microphones"], ["com.rode."],
         .init(vendor: "RØDE", updateRoute: "RØDE Central", url: URL(string: "https://rode.com/software"), managerBundleIdentifier: nil, note: nil)),
        (["shure", "shure incorporated", "shure inc."], ["com.shure."],
         .init(vendor: "Shure", updateRoute: "ShurePlus MOTIV and the support page", url: URL(string: "https://www.shure.com/support"), managerBundleIdentifier: nil, note: nil)),
        (["softube", "softube ab"], ["com.softube.", "org.softube."],
         .init(vendor: "Softube", updateRoute: "Softube Central", url: URL(string: "https://www.softube.com/softube-central"), managerBundleIdentifier: nil, note: nil)),
        (["sam", "samsung", "samsung electronics"], ["com.samsung."],
         .init(vendor: "Samsung", updateRoute: "the display's own firmware update", url: URL(string: "https://www.samsung.com/support/"), managerBundleIdentifier: nil,
               note: "A monitor or TV can appear as an audio output over DisplayPort or HDMI. Its firmware comes from the display maker, not from an audio driver.")),
    ]

    private static func key(_ value: String) -> String { value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Matches a Core Audio or Core MIDI manufacturer string exactly (case-insensitive). No fuzzy guessing.
    public static func matching(manufacturer: String) -> HardwareVendorGuide? {
        let needle = key(manufacturer)
        return entries.first { $0.names.contains(needle) }?.guide
    }

    /// Matches a driver's bundle identifier by reviewed vendor prefix.
    public static func matching(bundleIdentifier: String?) -> HardwareVendorGuide? {
        guard let id = bundleIdentifier?.lowercased() else { return nil }
        return entries.first { $0.prefixes.contains { id.hasPrefix($0) } }?.guide
    }
}

/// What a detected driver is, in one or two sentences a producer can act on.
public enum DriverDescription {
    public static func describe(_ driver: DriverRecord) -> String {
        let guide = HardwareVendorGuide.matching(bundleIdentifier: driver.bundleIdentifier)
        let what: String
        switch driver.kind {
        case let kind where kind.hasPrefix("Core Audio driver"):
            what = "A Core Audio plug-in. It adds an audio device to macOS, either for hardware or as a virtual device that routes sound between apps."
        case let kind where kind.hasPrefix("MIDI driver"):
            what = "A Core MIDI driver. It lets macOS talk to a MIDI interface or controller."
        default:
            what = "A system-level audio driver. It runs with elevated privileges and is installed by a vendor installer."
        }
        if let guide {
            let updates = "Updates: \(guide.updateRoute)."
            return [what, guide.note ?? "Made by \(guide.vendor).", updates].joined(separator: " ")
        }
        if let provenance = driver.provenance, provenance.signature == .apple {
            return "\(what) Signed by Apple and installed with macOS; it is not a third-party driver. Updates: macOS updates."
        }
        if let signer = driver.provenance?.signer, [.developerID, .macAppStore].contains(driver.provenance?.signature) {
            return "\(what) Signed by \(signer)\(driver.provenance?.copyright.map { " (\($0))" } ?? ""). MK Studio Upkeep has no reviewed update route for this maker yet; check that maker's website or the app that installed it."
        }
        if let copyright = driver.provenance?.copyright {
            return "\(what) Its copyright line reads “\(copyright)”, but it is not signed with a verified identity. Check which of your devices or apps installed it before changing anything."
        }
        if let id = driver.bundleIdentifier, let vendor = vendorLabel(from: id) {
            return "\(what) Its identifier points to \(vendor). MK Studio Upkeep has no reviewed information about this maker; check which of your devices or apps installed it before changing anything."
        }
        return "\(what) The maker could not be determined from its metadata or signature. Check which of your devices or apps installed it before changing anything."
    }

    /// Short maker label for a list row.
    public static func maker(of driver: DriverRecord) -> String {
        if let guide = HardwareVendorGuide.matching(bundleIdentifier: driver.bundleIdentifier) { return guide.vendor }
        if driver.provenance?.signature == .apple { return "Apple" }
        if let signer = driver.provenance?.signer, [.developerID, .macAppStore].contains(driver.provenance?.signature) { return signer }
        return vendorLabel(from: driver.bundleIdentifier ?? "").map { "Maker \($0)" } ?? "Unknown maker"
    }

    /// Plain-text details a user can paste into a report so the maintainer can add a
    /// reviewed entry. Contains no user name, home folder, path or device serial; only the
    /// standard folder the driver sits in.
    public static func maintainerReport(for driver: DriverRecord) -> String {
        let folder = driver.path.deletingLastPathComponent().path.hasPrefix("/Library/") ? driver.path.deletingLastPathComponent().path : "a user Library folder"
        return """
        Unknown driver report (MK Studio Upkeep)
        Name: \(driver.name)
        Kind: \(driver.kind)
        Bundle identifier: \(driver.bundleIdentifier ?? "none")
        Version: \(driver.version ?? "unknown")
        Folder: \(folder)
        Signature: \(driver.provenance?.signature.rawValue ?? "not read")\(driver.provenance?.signer.map { " · \($0)" } ?? "")\(driver.provenance?.teamIdentifier.map { " · team \($0)" } ?? "")
        Copyright: \(driver.provenance?.copyright ?? "none")
        """
    }
    /// One line for a list row: where updates come from.
    public static func route(for driver: DriverRecord) -> String {
        if (driver.bundleIdentifier ?? "").hasPrefix("com.apple.") { return "Part of macOS · updated with macOS" }
        return HardwareVendorGuide.matching(bundleIdentifier: driver.bundleIdentifier).map { "Updates: \($0.updateRoute)" } ?? "No reviewed update route"
    }

    /// "com.rogueamoeba.ACE.driver" → "rogueamoeba". Never used to guess a vendor's identity for evidence.
    static func vendorLabel(from bundleIdentifier: String) -> String? {
        let parts = bundleIdentifier.split(separator: ".")
        guard parts.count >= 2, ["com", "net", "org", "de", "se", "jp", "co", "io", "audio"].contains(parts[0].lowercased()) else { return nil }
        let label = parts[0].lowercased() == "jp" && parts.count >= 3 ? parts[2] : parts[1]
        return label.isEmpty ? nil : "“\(label)”"
    }
}

public extension AudioHardwareRecord {
    var guide: HardwareVendorGuide? { HardwareVendorGuide.matching(manufacturer: manufacturer) }
    var isBuiltIn: Bool { transport == "Built-in" }
}
public extension MIDIHardwareRecord {
    var guide: HardwareVendorGuide? { HardwareVendorGuide.matching(manufacturer: isSystemVirtual ? "Apple Inc." : manufacturer) }
    /// IAC, Network, UMP Network and the Bluetooth MIDI entry are provided by macOS, not by a connected device.
    var isSystemVirtual: Bool {
        let apple = manufacturer.isEmpty || manufacturer.lowercased().hasPrefix("apple")
        return apple && ["iac driver", "network", "ump network", "bluetooth"].contains(name.lowercased())
    }
}


/// Whether removing a driver is safe to offer, and how loudly to warn. `doNotDelete` is
/// shown in red everywhere the item appears; it never depends on guesswork about names.
public enum RemovalProtection: Equatable, Sendable {
    case none
    /// Removable, with a consequence the user should read first.
    case caution(String)
    /// Part of macOS, a system extension, or a driver a present device depends on.
    case doNotDelete(String)

    public var isRed: Bool { if case .doNotDelete = self { return true }; return false }
    public var headline: String? {
        switch self {
        case .none: nil
        case .caution: "Read before removing"
        case .doNotDelete: "Don’t delete this"
        }
    }
    public var reason: String? {
        switch self {
        case .none: nil
        case let .caution(text), let .doNotDelete(text): text
        }
    }
}

public enum DriverProtection {
    public static func isSystemComponent(bundleIdentifier: String?, path: URL) -> Bool {
        (bundleIdentifier ?? "").lowercased().hasPrefix("com.apple.") || path.path.hasPrefix("/System/")
    }

    /// Devices from the same maker as the driver, excluding built-in audio. A dependency is
    /// likely, not proven; the wording says so.
    public static func dependents(of driver: DriverRecord, devices: [AudioHardwareRecord]) -> [String] {
        guard let vendor = HardwareVendorGuide.matching(bundleIdentifier: driver.bundleIdentifier)?.vendor else { return [] }
        return devices.filter { !$0.isBuiltIn && $0.guide?.vendor == vendor }.map(\.name)
    }

    public static func assess(_ driver: DriverRecord, devices: [AudioHardwareRecord]) -> RemovalProtection {
        if isSystemComponent(bundleIdentifier: driver.bundleIdentifier, path: driver.path) {
            return .doNotDelete("Part of macOS. Apple installs, updates and removes it with the system, and audio features can stop working without it.")
        }
        let dependents = dependents(of: driver, devices: devices)
        let dependentText = dependents.isEmpty ? "" : " Your \(dependents.joined(separator: ", ")) \(dependents.count == 1 ? "depends" : "depend") on it."
        let ext = driver.path.pathExtension.lowercased()
        if ext == "kext" || ext == "systemextension" {
            return .doNotDelete("A system-level audio driver. Deleting the file does not unload it and can break audio or the next start-up; remove it only through the maker’s uninstaller.\(dependentText)")
        }
        if !dependents.isEmpty {
            return .doNotDelete("A device you have relies on this driver.\(dependentText) Remove it only if you are retiring that device, and prefer the maker’s uninstaller.")
        }
        return .caution("Removing it takes away the audio or MIDI device it provides, and apps that route through it will lose it.")
    }
}
