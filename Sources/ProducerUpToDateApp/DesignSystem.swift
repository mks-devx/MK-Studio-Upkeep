// SPDX-License-Identifier: BUSL-1.1
import AppKit
import SwiftUI

enum StudioUpkeepPreference {
    static let scanOnLaunch = "scanOnLaunch"
    static let expandTechnicalDetails = "expandTechnicalDetails"
    static let sidebarPosition = "sidebarPosition"
    static let appearance = "appearance"
    static let accent = "accentColor"
    static let surfaceStyle = "surfaceStyle"
    static let postScanDestination = "postScanDestination"
    static let inventoryDensity = "inventoryDensity"
    static let scanDAWs = "scanDAWs"
    static let scanAudioUnits = "scanAudioUnits"
    static let scanVST3 = "scanVST3"
    static let scanVST2 = "scanVST2"
    static let scanCLAP = "scanCLAP"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case monochrome
    case blue
    case violet
    case amber

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        Color(
            nsColor: NSColor(
                name: nil,
                dynamicProvider: { appearance in
                    let isDark = appearance.bestMatch(
                        from: [.darkAqua, .aqua]
                    ) == .darkAqua

                    switch self {
                    case .monochrome:
                        return NSColor(
                            calibratedWhite: isDark ? 0.88 : 0.16,
                            alpha: 1
                        )
                    case .blue:
                        return NSColor(
                            calibratedRed: isDark ? 0.48 : 0.22,
                            green: isDark ? 0.66 : 0.42,
                            blue: isDark ? 0.90 : 0.68,
                            alpha: 1
                        )
                    case .violet:
                        return NSColor(
                            calibratedRed: isDark ? 0.68 : 0.42,
                            green: isDark ? 0.58 : 0.32,
                            blue: isDark ? 0.85 : 0.64,
                            alpha: 1
                        )
                    case .amber:
                        return NSColor(
                            calibratedRed: isDark ? 0.86 : 0.60,
                            green: isDark ? 0.67 : 0.39,
                            blue: isDark ? 0.35 : 0.10,
                            alpha: 1
                        )
                    }
                }
            )
        )
    }

    var softColor: Color {
        color.opacity(0.09)
    }

    static var current: AppAccent {
        guard
            let stored = UserDefaults.standard.string(
                forKey: StudioUpkeepPreference.accent
            ),
            let accent = AppAccent(rawValue: stored)
        else {
            return .monochrome
        }

        return accent
    }
}

enum AppSurfaceStyle: String, CaseIterable, Identifiable {
    case glass
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass:
            return "Glass"
        case .solid:
            return "Solid"
        }
    }
}

enum PostScanDestination: String, CaseIterable, Identifiable {
    case smart
    case updates
    case attention
    case plugins
    case daws

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart:
            return "Most important result"
        case .updates:
            return "Updates Available"
        case .attention:
            return "Needs Attention"
        case .plugins:
            return "Plugins"
        case .daws:
            return "DAWs"
        }
    }
}

enum InventoryDensity: String, CaseIterable, Identifiable {
    case compact
    case comfortable

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var rowPadding: CGFloat {
        switch self {
        case .compact:
            return 2
        case .comfortable:
            return 6
        }
    }
}

enum StudioUpkeepDesign {
    static var accent: Color {
        AppAccent.current.color
    }

    static var accentSoft: Color {
        AppAccent.current.softColor
    }
    static let warning = Color(
        nsColor: NSColor(
            name: nil,
            dynamicProvider: { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return NSColor(
                    calibratedWhite: match == .darkAqua ? 0.68 : 0.38,
                    alpha: 1
                )
            }
        )
    )
    // Protection is the only red semantic state; ordinary findings stay neutral.
    static let protection = Color(nsColor: .systemRed)
    static let critical = Color(
        nsColor: NSColor(
            name: nil,
            dynamicProvider: { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                return NSColor(
                    calibratedWhite: match == .darkAqua ? 0.94 : 0.10,
                    alpha: 1
                )
            }
        )
    )

    enum Space {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let regular: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 48
        static let hero: CGFloat = 64
    }
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: packagedIcon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var packagedIcon: NSImage {
        guard
            let iconURL = Bundle.main.url(
                forResource: "AppIcon",
                withExtension: "icns"
            ),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return NSApplication.shared.applicationIconImage
        }

        return icon
    }
}

private struct StudioCanvasBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(StudioUpkeepPreference.surfaceStyle)
    private var surfaceStyle = AppSurfaceStyle.glass.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        if surfaceStyle == AppSurfaceStyle.glass.rawValue && !reduceTransparency {
            content.background(.ultraThinMaterial)
        } else {
            content.background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct StudioPanelBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(StudioUpkeepPreference.surfaceStyle)
    private var surfaceStyle = AppSurfaceStyle.glass.rawValue

    @ViewBuilder
    func body(content: Content) -> some View {
        if surfaceStyle == AppSurfaceStyle.glass.rawValue && !reduceTransparency {
            content.background(.thinMaterial)
        } else {
            content.background(Color.primary.opacity(0.035))
        }
    }
}

extension View {
    func studioCanvasBackground() -> some View {
        modifier(StudioCanvasBackground())
    }

    func studioPanelBackground() -> some View {
        modifier(StudioPanelBackground())
    }

    @ViewBuilder
    func studioProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
