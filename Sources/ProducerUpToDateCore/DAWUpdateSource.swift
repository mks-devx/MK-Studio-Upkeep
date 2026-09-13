// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Navigation aids are separate from release evidence. These never use URLs from app metadata.
public enum DAWUpdateSource {
    public struct ReviewedDestination: Equatable, Sendable {
        public let url: URL
        public let referenceURL: URL
        public let reviewedOn: String
    }
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

    private static func reviewed(_ url: String, reviewedOn: String) -> ReviewedDestination {
        let referenceURL = URL(string: url)!
        return .init(url: referenceURL, referenceURL: referenceURL, reviewedOn: reviewedOn)
    }

    public static func reviewedDestination(for definitionID: String) -> ReviewedDestination? {
        let destinations: [String: ReviewedDestination] = [
            "ableton-live": reviewed("https://www.ableton.com/en/release-notes/", reviewedOn: "2026-09-13"),
            "logic-pro": reviewed("https://support.apple.com/en-us/109503", reviewedOn: "2026-09-13"),
            "garageband": reviewed("https://support.apple.com/en-us/109515", reviewedOn: "2026-09-13"),
            "fl-studio": reviewed("https://www.image-line.com/fl-studio-download/", reviewedOn: "2026-09-13"),
            "cubase": reviewed("https://www.steinberg.net/cubase/release-notes/", reviewedOn: "2026-09-13"),
            "nuendo": reviewed("https://www.steinberg.net/nuendo/", reviewedOn: "2026-09-13"),
            "pro-tools": reviewed("https://www.avid.com/pro-tools", reviewedOn: "2026-09-13"),
            "studio-one": reviewed("https://www.presonus.com/", reviewedOn: "2026-09-13"),
            "reaper": reviewed("https://www.reaper.fm/download.php", reviewedOn: "2026-09-13"),
            "bitwig-studio": reviewed("https://www.bitwig.com/download/", reviewedOn: "2026-09-13"),
            "reason": reviewed("https://www.reasonstudios.com/reason/updates/release-notes", reviewedOn: "2026-09-13"),
            "digital-performer": reviewed("https://motu.com/en-us/products/software/dp/", reviewedOn: "2026-09-13"),
            "maschine": reviewed("https://support.native-instruments.com/support/solutions/articles/69000881126-what-s-new-in-maschine-3-6", reviewedOn: "2026-09-13"),
            "waveform": reviewed("https://www.tracktion.com/", reviewedOn: "2026-09-13"),
            "luna": reviewed("https://www.uaudio.com/", reviewedOn: "2026-09-13"),
            "ardour": reviewed("https://ardour.org/", reviewedOn: "2026-09-13"),
            "renoise": reviewed("https://www.renoise.com/download/", reviewedOn: "2026-09-13"),
            "mixbus": reviewed("https://support.harrisonaudio.com/hc/en-gb/articles/14837072052125-Mixbus-Downloads", reviewedOn: "2026-09-13"),
            "mulab": reviewed("https://www.mutools.com/", reviewedOn: "2026-09-13"),
            "n-track": reviewed("https://ntrack.com/download.php", reviewedOn: "2026-09-13"),
            "lmms": reviewed("https://lmms.io/", reviewedOn: "2026-09-13"),
            "zrythm": reviewed("https://www.zrythm.org/", reviewedOn: "2026-09-13"),
            "mpc": reviewed("https://www.akaipro.com/mpc-release-notes", reviewedOn: "2026-09-13"),
            "fender-studio-pro": reviewed("https://support.fender.com/hc/en-us/articles/46787705756443-FENDER-STUDIO-PRO", reviewedOn: "2026-09-13")
        ]
        return destinations[definitionID].flatMap { destination in
            OfficialLinkReview.isComplete(referenceURL: destination.referenceURL, reviewedOn: destination.reviewedOn)
                ? destination : nil
        }
    }

    public static func destination(for definitionID: String) -> URL? {
        reviewedDestination(for: definitionID)?.url
    }
}
