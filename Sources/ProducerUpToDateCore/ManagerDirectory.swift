// SPDX-License-Identifier: AGPL-3.0-only
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
    public let referenceURL: URL
    public let reviewedOn: String
    /// A caveat about the route, for example that newer products moved to another app.
    public let note: String?

    public init(id: String, name: String, kind: String, productPrefixes: [String], url: URL? = nil, note: String? = nil, referenceURL: URL, reviewedOn: String) {
        self.id = id; self.name = name; self.kind = kind; self.productPrefixes = productPrefixes
        self.url = url; self.note = note; self.referenceURL = referenceURL; self.reviewedOn = reviewedOn
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

    private static func reviewed(id: String, name: String, kind: String, productPrefixes: [String], url: String, note: String? = nil, reviewedOn: String) -> Self {
        let referenceURL = URL(string: url)!
        return .init(id: id, name: name, kind: kind, productPrefixes: productPrefixes, url: referenceURL, note: note, referenceURL: referenceURL, reviewedOn: reviewedOn)
    }

    /// Maintained from the official developer references in docs/MANAGER_SOURCES.md.
    public static let known: [Self] = [
        reviewed(id: "Native Access", name: "Native Access", kind: "Software managers", productPrefixes: ["com.native-instruments."], url: "https://www.native-instruments.com/en/specials/native-access/", reviewedOn: "2026-09-08"),
        reviewed(id: "IK Product Manager", name: "IK Product Manager", kind: "Software managers", productPrefixes: ["com.ikmultimedia."], url: "https://www.ikmultimedia.com/products/productmanager/", reviewedOn: "2026-09-08"),
        reviewed(id: "Antelope Launcher", name: "Antelope Launcher", kind: "Software managers", productPrefixes: ["com.antelopeaudio."], url: "https://support.antelopeaudio.com/en/support/solutions/articles/42000111514-downloads", reviewedOn: "2026-09-08"),
        reviewed(id: "Arturia Software Center", name: "Arturia Software Center", kind: "Software managers", productPrefixes: ["com.arturia."], url: "https://www.arturia.com/support/downloads-manuals", reviewedOn: "2026-09-08"),
        reviewed(id: "UVI Portal", name: "UVI Portal", kind: "Software managers", productPrefixes: ["net.uvi.", "com.uvisoundsource."], url: "https://www.uvi.net/uvi-portal", reviewedOn: "2026-09-08"),
        reviewed(id: "Plugin Alliance Installation Manager", name: "Plugin Alliance Installation Manager", kind: "Software managers", productPrefixes: ["com.plugin-alliance."], url: "https://www.plugin-alliance.com/pages/installation-manager", reviewedOn: "2026-09-08"),
        reviewed(id: "BLEASS Plugins Installer", name: "BLEASS Plugins Installer", kind: "Software managers", productPrefixes: ["com.bleass."], url: "https://www.bleass.com/bpi-help/", reviewedOn: "2026-09-08"),
        reviewed(id: "Beatport Access", name: "Beatport Access", kind: "Software managers", productPrefixes: [], url: "https://help.pluginboutique.com/hc/en-us/articles/19021848952084-How-do-I-download-Beatport-Access", reviewedOn: "2026-09-08"),
        reviewed(id: "iLok License Manager", name: "iLok License Manager", kind: "Licence tools", productPrefixes: [], url: "https://help.ilok.com/faq_ilm.html", reviewedOn: "2026-09-08"),
        reviewed(id: "Waves Central", name: "Waves Central", kind: "Software managers", productPrefixes: ["com.waves."], url: "https://www.waves.com/downloads/central", reviewedOn: "2026-09-08"),
        reviewed(id: "Softube Central", name: "Softube Central", kind: "Software managers", productPrefixes: ["com.softube.", "org.softube."], url: "https://www.softube.com/us/support", reviewedOn: "2026-09-08"),
        reviewed(id: "MPluginManager", name: "MPluginManager", kind: "Software managers", productPrefixes: ["com.meldaproduction."], url: "https://www.meldaproduction.com/downloads", reviewedOn: "2026-09-08"),
        reviewed(id: "iZotope Product Portal", name: "iZotope Product Portal", kind: "Software managers", productPrefixes: ["com.izotope."], url: "https://support.izotope.com/hc/en-us/articles/6658125027345-Welcome-to-iZotope-Product-Portal", note: "Newer iZotope products are delivered by Native Access instead; check whichever of the two you use.", reviewedOn: "2026-09-08"),
        reviewed(id: "Steinberg Download Assistant", name: "Steinberg Download Assistant", kind: "Software managers", productPrefixes: ["com.steinberg."], url: "https://o.steinberg.net/en/support/downloads/steinberg_download_assistant.html", reviewedOn: "2026-09-08"),
        reviewed(id: "Steinberg Activation Manager", name: "Steinberg Activation Manager", kind: "Licence tools", productPrefixes: [], url: "https://o.steinberg.net/en/support/downloads/steinberg_activation_manager.html", reviewedOn: "2026-09-08"),
        reviewed(id: "Focusrite Control 2", name: "Focusrite Control 2", kind: "Hardware managers", productPrefixes: ["com.focusrite."], url: "https://focusrite.com/software/focusrite-control-2", reviewedOn: "2026-09-08"),
        reviewed(id: "UA Connect", name: "UA Connect", kind: "Hardware managers", productPrefixes: ["com.uaudio."], url: "https://www.uaudio.com/products/ua-connect", reviewedOn: "2026-09-08"),
        reviewed(id: "Universal Control", name: "Universal Control", kind: "Hardware managers", productPrefixes: ["com.presonus."], url: "https://support.presonus.com/hc/en-us/articles/42636356381709-PreSonus-Universal-Control-is-now-called-Fender-Universal-Control-v5-for-Mac-and-PC", reviewedOn: "2026-09-08"),
        reviewed(id: "Elektron Transfer", name: "Elektron Transfer", kind: "Hardware managers", productPrefixes: [], url: "https://support.elektron.se/support/solutions/43000366333", reviewedOn: "2026-09-08"),
        reviewed(id: "Overbridge", name: "Overbridge", kind: "Hardware managers", productPrefixes: ["se.elektron."], url: "https://support.elektron.se/support/solutions/articles/43000570186-installing-overbridge", reviewedOn: "2026-09-08"),
        reviewed(id: "Novation Components", name: "Novation Components", kind: "Hardware managers", productPrefixes: ["com.novation.", "com.focusrite.novation."], url: "https://novationmusic.com/components", reviewedOn: "2026-09-08"),
        reviewed(id: "inMusic Software Center", name: "inMusic Software Center", kind: "Software managers", productPrefixes: ["com.inmusic.", "com.airmusictech.", "com.akaipro."], url: "https://support.airmusictech.com/support/solutions/69000438271", reviewedOn: "2026-09-08"),
        reviewed(id: "Audio Modeling Software Center", name: "Audio Modeling Software Center", kind: "Software managers", productPrefixes: ["com.audiomodeling."], url: "https://audiomodeling.com/support/install", reviewedOn: "2026-09-08"),
        reviewed(id: "RØDE Central", name: "RØDE Central", kind: "Hardware managers", productPrefixes: ["com.rode."], url: "https://rode.com/en/apps/rode-central", reviewedOn: "2026-09-08"),
        reviewed(id: "Kilohearts Installer", name: "Kilohearts Installer", kind: "Software managers", productPrefixes: ["com.kilohearts."], url: "https://kilohearts.com/download", reviewedOn: "2026-09-08"),
        reviewed(id: "Splice", name: "Splice", kind: "Software managers", productPrefixes: [], url: "https://splice.com/download", reviewedOn: "2026-09-08")
    ]

    public static func matching(identifiers: [String]) -> Self? {
        guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
        let matches = known.filter { manager in
            identifiers.allSatisfy { id in manager.productPrefixes.contains { id.lowercased().hasPrefix($0) } }
        }
        return matches.count == 1 ? matches.first : nil
    }
}
