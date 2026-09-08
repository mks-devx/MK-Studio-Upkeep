// SPDX-License-Identifier: BUSL-1.1
import Foundation

/// Known identities, not a claim of universal discovery or installation ownership.
/// App names and official destinations are documented in docs/MANAGER_SOURCES.md.
/// Product prefixes are routing hints, not verified publisher identities.
public struct ManagerDefinition: Identifiable, Hashable, Sendable {
    /// Stable display identity; never interpreted as an application bundle identifier.
    public let id: String
    public let name: String
    public let kind: String
    public let productPrefixes: [String]
    /// Vendor website for a "Get …" link when the app is not installed.
    public let url: URL?
    /// A caveat about the route, for example that newer products moved to another app.
    public let note: String?

    public init(id: String, name: String, kind: String, productPrefixes: [String], url: URL? = nil, note: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.productPrefixes = productPrefixes; self.url = url; self.note = note
    }
    /// Display name used to find the app by name when the identifier is unknown or differs.
    public var appName: String { name }
    /// Officially named components and branding variants, not publisher verification.
    public var appNames: [String] {
        switch name {
        case "Plugin Alliance Installation Manager": return ["Plugin Alliance Installation Manager", "PA Installation Manager", "PA-InstallationManager"]
        case "Overbridge": return ["Overbridge Control Panel", "Overbridge"]
        case "Universal Control": return ["Universal Control", "Fender Universal Control"]
        case "RØDE Central": return ["RØDE Central", "RODE Central", "Rode Central"]
        case "Elektron Transfer": return ["Elektron Transfer", "Transfer"]
        default: return [name]
        }
    }

    /// Maintained from the official developer references in docs/MANAGER_SOURCES.md.
    public static let known: [Self] = [
        .init(id: "Native Access", name: "Native Access", kind: "Software managers", productPrefixes: ["com.native-instruments."], url: URL(string: "https://www.native-instruments.com/en/specials/native-access/")),
        .init(id: "IK Product Manager", name: "IK Product Manager", kind: "Software managers", productPrefixes: ["com.ikmultimedia."], url: URL(string: "https://www.ikmultimedia.com/products/productmanager/")),
        .init(id: "Antelope Launcher", name: "Antelope Launcher", kind: "Software managers", productPrefixes: ["com.antelopeaudio."], url: URL(string: "https://support.antelopeaudio.com/en/support/solutions/articles/42000111514-downloads")),
        .init(id: "Arturia Software Center", name: "Arturia Software Center", kind: "Software managers", productPrefixes: ["com.arturia."], url: URL(string: "https://www.arturia.com/support/downloads-manuals")),
        .init(id: "UVI Portal", name: "UVI Portal", kind: "Software managers", productPrefixes: ["net.uvi.", "com.uvisoundsource."], url: URL(string: "https://www.uvi.net/uvi-portal")),
        .init(id: "Plugin Alliance Installation Manager", name: "Plugin Alliance Installation Manager", kind: "Software managers", productPrefixes: ["com.plugin-alliance."], url: URL(string: "https://www.plugin-alliance.com/pages/installation-manager")),
        .init(id: "BLEASS Plugins Installer", name: "BLEASS Plugins Installer", kind: "Software managers", productPrefixes: ["com.bleass."], url: URL(string: "https://www.bleass.com/bpi-help/")),
        .init(id: "Beatport Access", name: "Beatport Access", kind: "Software managers", productPrefixes: [], url: URL(string: "https://help.pluginboutique.com/hc/en-us/articles/19021848952084-How-do-I-download-Beatport-Access")),
        .init(id: "iLok License Manager", name: "iLok License Manager", kind: "Licence tools", productPrefixes: [], url: URL(string: "https://help.ilok.com/faq_ilm.html")),
        .init(id: "Waves Central", name: "Waves Central", kind: "Software managers", productPrefixes: ["com.waves."], url: URL(string: "https://www.waves.com/downloads/central")),
        .init(id: "Softube Central", name: "Softube Central", kind: "Software managers", productPrefixes: ["com.softube.", "org.softube."], url: URL(string: "https://www.softube.com/us/support")),
        .init(id: "MPluginManager", name: "MPluginManager", kind: "Software managers", productPrefixes: ["com.meldaproduction."], url: URL(string: "https://www.meldaproduction.com/downloads")),
        .init(id: "iZotope Product Portal", name: "iZotope Product Portal", kind: "Software managers", productPrefixes: ["com.izotope."], url: URL(string: "https://support.izotope.com/hc/en-us/articles/6658125027345-Welcome-to-iZotope-Product-Portal"), note: "Newer iZotope products are delivered by Native Access instead; check whichever of the two you use."),
        .init(id: "Steinberg Download Assistant", name: "Steinberg Download Assistant", kind: "Software managers", productPrefixes: ["com.steinberg."], url: URL(string: "https://o.steinberg.net/en/support/downloads/steinberg_download_assistant.html")),
        .init(id: "Steinberg Activation Manager", name: "Steinberg Activation Manager", kind: "Licence tools", productPrefixes: [], url: URL(string: "https://o.steinberg.net/en/support/downloads/steinberg_activation_manager.html")),
        .init(id: "Focusrite Control 2", name: "Focusrite Control 2", kind: "Hardware managers", productPrefixes: ["com.focusrite."], url: URL(string: "https://focusrite.com/software/focusrite-control-2")),
        .init(id: "UA Connect", name: "UA Connect", kind: "Hardware managers", productPrefixes: ["com.uaudio."], url: URL(string: "https://www.uaudio.com/products/ua-connect")),
        .init(id: "Universal Control", name: "Universal Control", kind: "Hardware managers", productPrefixes: ["com.presonus."], url: URL(string: "https://support.presonus.com/hc/en-us/articles/42636356381709-PreSonus-Universal-Control-is-now-called-Fender-Universal-Control-v5-for-Mac-and-PC")),
        .init(id: "Elektron Transfer", name: "Elektron Transfer", kind: "Hardware managers", productPrefixes: [], url: URL(string: "https://support.elektron.se/support/solutions/43000366333")),
        .init(id: "Overbridge", name: "Overbridge", kind: "Hardware managers", productPrefixes: ["se.elektron."], url: URL(string: "https://support.elektron.se/support/solutions/articles/43000570186-installing-overbridge")),
        .init(id: "Novation Components", name: "Novation Components", kind: "Hardware managers", productPrefixes: ["com.novation.", "com.focusrite.novation."], url: URL(string: "https://novationmusic.com/components")),
        .init(id: "inMusic Software Center", name: "inMusic Software Center", kind: "Software managers", productPrefixes: ["com.inmusic.", "com.airmusictech.", "com.akaipro."], url: URL(string: "https://support.airmusictech.com/support/solutions/69000438271")),
        .init(id: "Audio Modeling Software Center", name: "Audio Modeling Software Center", kind: "Software managers", productPrefixes: ["com.audiomodeling."], url: URL(string: "https://audiomodeling.com/support/install")),
        .init(id: "RØDE Central", name: "RØDE Central", kind: "Hardware managers", productPrefixes: ["com.rode."], url: URL(string: "https://rode.com/en/apps/rode-central")),
        .init(id: "Kilohearts Installer", name: "Kilohearts Installer", kind: "Software managers", productPrefixes: ["com.kilohearts."], url: URL(string: "https://kilohearts.com/download")),
        .init(id: "Splice", name: "Splice", kind: "Software managers", productPrefixes: [], url: URL(string: "https://splice.com/download"))
    ]

    public static func matching(identifiers: [String]) -> Self? {
        guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
        let matches = known.filter { manager in
            identifiers.allSatisfy { id in manager.productPrefixes.contains { id.lowercased().hasPrefix($0) } }
        }
        return matches.count == 1 ? matches.first : nil
    }
}
