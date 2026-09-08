// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Navigation aids are separate from release evidence. These never use URLs from app metadata.
public enum DAWUpdateSource {
    /// Mac App Store handoff for bundles carrying a receipt. The Updates page is generic;
    /// a product page is offered only for a recognised bundle identity with a known store ID.
    public struct AppStoreDestination: Equatable, Sendable {
        public let updates: URL
        public let product: URL?
    }
    static let appStoreIDs = ["logic-pro": "634148309", "garageband": "682658836"]

    public static func appStoreDestination(for daw: InstalledDAWRecord) -> AppStoreDestination? {
        guard daw.installedFromAppStore, let updates = URL(string: "macappstore://showUpdatesPage") else { return nil }
        let product = daw.identityIsInferred ? nil
            : appStoreIDs[daw.definitionID].flatMap { URL(string: "macappstore://apps.apple.com/app/id\($0)") }
        return AppStoreDestination(updates: updates, product: product)
    }

    public static func destination(for definitionID: String) -> URL? {
        let destinations = [
            "ableton-live": "https://www.ableton.com/en/release-notes/",
            "logic-pro": "https://support.apple.com/en-us/109503",
            "garageband": "https://support.apple.com/en-us/109515",
            "fl-studio": "https://www.image-line.com/fl-studio-download/",
            "cubase": "https://www.steinberg.net/cubase/release-notes/",
            "nuendo": "https://www.steinberg.net/nuendo/",
            "pro-tools": "https://www.avid.com/pro-tools",
            "studio-one": "https://www.presonus.com/",
            "reaper": "https://www.reaper.fm/download.php",
            "bitwig-studio": "https://www.bitwig.com/download/",
            "reason": "https://www.reasonstudios.com/reason/updates/release-notes",
            "digital-performer": "https://motu.com/en-us/products/software/dp/",
            "maschine": "https://support.native-instruments.com/support/solutions/articles/69000881126-what-s-new-in-maschine-3-6",
            "waveform": "https://www.tracktion.com/",
            "luna": "https://www.uaudio.com/",
            "ardour": "https://ardour.org/",
            "renoise": "https://www.renoise.com/download/",
            "mixbus": "https://support.harrisonaudio.com/hc/en-gb/articles/14837072052125-Mixbus-Downloads",
            "mulab": "https://www.mutools.com/",
            "n-track": "https://ntrack.com/download.php",
            "lmms": "https://lmms.io/",
            "zrythm": "https://www.zrythm.org/",
            "mpc": "https://www.akaipro.com/mpc-release-notes",
            "fender-studio-pro": "https://support.fender.com/hc/en-us/articles/46787705756443-FENDER-STUDIO-PRO"
        ]
        return destinations[definitionID].flatMap(URL.init(string:))
    }
}
