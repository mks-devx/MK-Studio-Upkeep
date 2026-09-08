// SPDX-License-Identifier: MPL-2.0
import ProducerUpToDateCore
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case scanning
    case evidence
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .scanning:
            return "Scanning"
        case .evidence:
            return "Evidence"
        case .about:
            return "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Choose how MK Studio Upkeep starts and presents your inventory."
        case .scanning:
            return "Decide which studio software locations are included."
        case .evidence:
            return "Control detail levels and review the app's trust policy."
        case .about:
            return "Product information, documentation, and version details."
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .scanning:
            return "magnifyingglass"
        case .evidence:
            return "checkmark.seal"
        case .about:
            return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SettingsSection = .general
    @State private var showsWelcomeSetup = false
    @State private var showsManual = false
    @State private var restoredDefaults = false
    @StateObject private var appUpdates = AppUpdateModel()
    @AppStorage("includeAppBetaReleases") private var includeAppBetas = false

    @AppStorage(StudioUpkeepPreference.sidebarPosition) private var sidebarPosition = "left"
    @AppStorage("showPluginCategories") private var showCategories = true
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage(MenuBarAudioSummary.preferenceKey) private var showMenuBarAudio = true
    @AppStorage(StudioUpkeepPreference.scanOnLaunch)
    private var scanOnLaunch = false
    @AppStorage(StudioUpkeepPreference.expandTechnicalDetails)
    private var expandTechnicalDetails = false
    @AppStorage(StudioUpkeepPreference.appearance)
    private var appearance = AppAppearance.system.rawValue
    @AppStorage(StudioUpkeepPreference.accent)
    private var accent = AppAccent.monochrome.rawValue
    @AppStorage(StudioUpkeepPreference.surfaceStyle)
    private var surfaceStyle = AppSurfaceStyle.glass.rawValue
    @AppStorage(StudioUpkeepPreference.postScanDestination)
    private var postScanDestination = PostScanDestination.smart.rawValue
    @AppStorage(StudioUpkeepPreference.inventoryDensity)
    private var inventoryDensity = InventoryDensity.comfortable.rawValue
    @AppStorage(StudioUpkeepPreference.scanDAWs)
    private var scanDAWs = true
    @AppStorage(StudioUpkeepPreference.scanAudioUnits)
    private var scanAudioUnits = true
    @AppStorage(StudioUpkeepPreference.scanVST3)
    private var scanVST3 = true
    @AppStorage(StudioUpkeepPreference.scanVST2)
    private var scanVST2 = true
    @AppStorage(StudioUpkeepPreference.scanCLAP)
    private var scanCLAP = true

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 188)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageHeader
                    activePage
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, StudioUpkeepDesign.Space.xLarge)
                .padding(.vertical, StudioUpkeepDesign.Space.large)
            }
            .id(selection)
        }
        .studioCanvasBackground()
        .tint(selectedAccent.color)
        .sheet(isPresented: $showsManual) { StudioUpkeepHelpView().environmentObject(model) }
        .sheet(isPresented: $showsWelcomeSetup) {
            OnboardingView(title: "Welcome setup")
                .environmentObject(model)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: StudioUpkeepDesign.Space.medium) {
                AppIconView(size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MK Studio Upkeep")
                        .font(.headline)
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, StudioUpkeepDesign.Space.regular)
            .padding(.top, StudioUpkeepDesign.Space.large)
            .padding(.bottom, StudioUpkeepDesign.Space.regular)

            VStack(spacing: StudioUpkeepDesign.Space.xSmall) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarButton(section)
                }
            }
            .padding(.horizontal, StudioUpkeepDesign.Space.small)

            Spacer()

            Text("VERSION " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"))
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(StudioUpkeepDesign.Space.regular)
        }
        .studioPanelBackground()
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        Button {
            selection = section
        } label: {
            HStack(spacing: StudioUpkeepDesign.Space.medium) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()
            }
            .foregroundStyle(
                selection == section ? Color.primary : Color.secondary
            )
            .padding(.horizontal, StudioUpkeepDesign.Space.medium)
            .padding(.vertical, 9)
            .background(
                selection == section
                    ? StudioUpkeepDesign.accentSoft
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selection == section ? "Selected" : "")
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
            Text(selection.title)
                .font(.system(size: 27, weight: .semibold))
                .tracking(-0.35)

            Text(selection.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, StudioUpkeepDesign.Space.xLarge)
    }

    @ViewBuilder
    private var activePage: some View {
        switch selection {
        case .general:
            general
        case .scanning:
            scanning
        case .evidence:
            evidence
        case .about:
            about
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.xLarge) {
            Text("No tracking or automatic crash uploads. Use Help → Report a bug to preview a report before opening it on GitHub.")
                .font(.callout).foregroundStyle(.secondary)

            settingsGroup("App visibility") {
                Toggle("Show MK Studio Upkeep in the Dock", isOn: Binding(get: { showDockIcon }, set: { value in
                    if !value { showMenuBar = true }
                    showDockIcon = value
                }))
                Toggle("Show MK Studio Upkeep in the menu bar", isOn: Binding(get: { showMenuBar }, set: { value in
                    if !value { showDockIcon = true }
                    showMenuBar = value
                }))
                Text("At least one icon stays visible. Either mouse button opens the menu-bar controls.").font(.caption).foregroundStyle(.secondary)
            }
            settingsGroup("Menu bar audio") {
                Toggle("Show audio settings beside the menu-bar icon", isOn: $showMenuBarAudio)
                Text("Sample rate, device bit depth and buffer size for the macOS output device. Refreshed every five seconds; your DAW may use different settings.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !showMenuBar {
                    Text("Enable the menu-bar icon above to see these readings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            settingsGroup("Welcome") {
                settingsRow("Welcome setup", detail: "Review the introduction and scan choices using your current settings.") {
                    Button("Open welcome setup…") { showsWelcomeSetup = true }
                        .help("Reopen the welcome wizard. Your current scan choices are kept; no scan starts until you choose Scan This Mac.")
                        .disabled(model.isScanning)
                }
                if model.isScanning {
                    Text("Wait for the current scan to finish, or cancel it, before reopening setup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            settingsGroup("Behaviour") {
                settingsRow(
                    "Scan on launch",
                    detail: "Start a read-only inventory when the app opens."
                ) {
                    Toggle("Scan on launch", isOn: $scanOnLaunch)
                        .labelsHidden()
                }

                rowDivider

                settingsRow(
                    "After the first scan",
                    detail: "Choose the initial results view. Rescans keep your current view and filters."
                ) {
                    Picker("After the first scan", selection: $postScanDestination) {
                        ForEach(PostScanDestination.allCases.filter { $0 != .updates }) { destination in
                            Text(destination.title)
                                .tag(destination.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }

            settingsGroup("Presentation") {
                settingsRow("Sidebar position", detail: "Place navigation on the left, right or top of the main window.") {
                    Picker("Sidebar position", selection: $sidebarPosition) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                        Text("Top").tag("top")
                    }.labelsHidden().frame(width: 150)
                }
                rowDivider
                Toggle("Show plugin categories", isOn: $showCategories)
                Text("Show category labels and a category filter in Plugins. Categories come from the plugins’ own metadata; unclear ones stay Uncategorised.")
                    .font(.caption).foregroundStyle(.secondary)
                rowDivider
                settingsRow(
                    "Appearance",
                    detail: "Follow macOS or keep a light or dark workspace."
                ) {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                rowDivider

                settingsRow(
                    "Accent",
                    detail: "Choose a restrained highlight while health states stay neutral."
                ) {
                    accentPicker
                }

                rowDivider

                settingsRow(
                    "Surface",
                    detail: "Use translucent material or a fully opaque workspace."
                ) {
                    Picker("Surface", selection: $surfaceStyle) {
                        ForEach(AppSurfaceStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                rowDivider

                settingsRow(
                    "Inventory spacing",
                    detail: "Choose how much information fits in each table."
                ) {
                    Picker("Inventory spacing", selection: $inventoryDensity) {
                        ForEach(InventoryDensity.allCases) { density in
                            Text(density.title).tag(density.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            Button {
                restoreRecommendedSettings()
            } label: {
                Label(
                    "Restore presentation and scan defaults",
                    systemImage: "arrow.counterclockwise"
                )
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text("Resets appearance, visibility, detail and scan choices. Additional plugin folders and app-update preferences are kept.")
                .font(.caption).foregroundStyle(.secondary)
            if restoredDefaults {
                Text("Presentation and scan defaults restored. Additional plugin folders were kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var scanning: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.large) {
            settingsGroup("Scan coverage") {
                scanToggle(
                    "Audio Units",
                    detail: "System and user Components folders",
                    isOn: $scanAudioUnits
                )
                rowDivider
                scanToggle(
                    "VST3",
                    detail: "System and user VST3 folders",
                    isOn: $scanVST3
                )
                rowDivider
                scanToggle(
                    "VST2",
                    detail: "Legacy VST folders",
                    isOn: $scanVST2
                )
                rowDivider
                scanToggle(
                    "CLAP",
                    detail: "System and user CLAP folders",
                    isOn: $scanCLAP
                )
                rowDivider
                scanToggle(
                    "DAW applications",
                    detail: "System and user Applications folders",
                    isOn: $scanDAWs
                )
            }

            settingsGroup("Additional plugin folders") {
                Text("These folders and their subfolders are scanned too. Pick plugin folders, not a whole disk.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.customPluginFolders, id: \.self) { path in
                    HStack {
                        Text(path).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button("Remove from scan") { model.removePluginFolder(path) }.help("Stop scanning this folder. Its files are kept.")
                            .accessibilityLabel("Remove \(path) from scan locations")
                    }
                }
                Button("Include folder…") { model.addPluginFolder() }.help("Choose an additional plugin folder to scan.")
                Text("Removing a folder here only changes what is scanned. No files are touched. Rescan to apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            note(
                symbol: "lock.open.display",
                text: "Changes apply to the next scan. MK Studio Upkeep reads bundle metadata without loading third-party plugin code."
            )
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.xLarge) {
            settingsGroup("Your privacy") {
                Text("No tracking. Your scan data stays on your Mac.").font(.headline)
                Text("MK Studio Upkeep does not upload your plugin or DAW inventory, file paths, hardware details or activity readings. There are no analytics, advertising trackers or automatic crash-report uploads.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Scanning and website matching run locally. Links open your browser; software managers use their own privacy policies. No plugin inventory is uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Bug reports are previewed first. Opening the GitHub report form sends that preview to GitHub; you decide whether to submit it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            settingsGroup("Inspection") {
                settingsRow(
                    "Technical details",
                    detail: "Expand technical details for plugins, DAWs and drivers. Changes apply to open views."
                ) {
                    Toggle("Expand technical details", isOn: $expandTechnicalDetails)
                        .labelsHidden()
                }

                rowDivider

                readOnlyRow(
                    "Product information",
                    value: "Installed files and developer links"
                )

                rowDivider

                readOnlyRow(
                    "Unknown results",
                    value: "Never treated as current"
                )
            }

            settingsGroup("Removal safety") {
                note(
                    symbol: "lock.shield",
                    text: "Uninstall previews selected software bundles and moves confirmed items to Trash. External support and creative content are preserved."
                )
            }

            Button {
                showsManual = true
            } label: {
                HStack {
                    Label("Open the user manual", systemImage: "book.closed")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.xLarge) {
            HStack(alignment: .center, spacing: StudioUpkeepDesign.Space.large) {
                AppIconView(size: 84)

                VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
                    Text("MK Studio Upkeep")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.3)
                    Text("Your audio software, at a glance.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text(
                "A free app for keeping track of your music software. See your installed plugins and DAWs, find developer websites, and review compatibility and uninstall options."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            settingsGroup("Application") {
                readOnlyRow("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                rowDivider
                readOnlyRow("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Development")
                rowDivider
                Text(TestedPlatform.requirements).font(.callout).fixedSize(horizontal: false, vertical: true)
                if !TestedPlatform.isTestedConfiguration { Text(TestedPlatform.removalCaution).font(.caption).foregroundStyle(.secondary) }
                rowDivider
                readOnlyRow("Licence", value: "Mozilla Public License 2.0")
                Text("Free, open-source software for personal and professional use. Use, modification and redistribution, including commercial use, are permitted under MPL-2.0. See the licence and source information for distribution requirements.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Product and company names identify software found on your Mac and belong to their owners. MK Studio Upkeep is not affiliated with or endorsed by any of them.")
                    .font(.caption).foregroundStyle(.secondary)
                if let licenceURL = Bundle.main.url(forResource: "LICENSE", withExtension: nil) {
                    Button("Read licence") { NSWorkspace.shared.open(licenceURL) }.help("Open the licence document.")
                }
                if let sourceURL = Bundle.main.url(forResource: "LICENSING", withExtension: "md") {
                    Button("Licence and source information") { NSWorkspace.shared.open(sourceURL) }
                }
            }

            Text("No tracking or automatic crash uploads. Use Help → Report a bug to preview a report before opening it on GitHub.")
                .font(.callout).foregroundStyle(.secondary)

            applicationUpdates

            VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.large) {
                VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
                    Text("Project")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://github.com/mks-devx/MK-Studio-Upkeep")!) {
                        HStack(spacing: StudioUpkeepDesign.Space.small) {
                            Text("Source and releases on GitHub")
                                .font(.title3.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .tint(.primary)
                    .help("Open the project on GitHub")
                    .accessibilityLabel("Project on GitHub")
                }

                Divider()

                Button {
                    showsManual = true
                } label: {
                    HStack(spacing: StudioUpkeepDesign.Space.small) {
                        Label("User manual", systemImage: "book.closed")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, StudioUpkeepDesign.Space.small)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Read the MK Studio Upkeep user manual")
            }
        }
    }

    private var applicationUpdates: some View {
        settingsGroup("MK Studio Upkeep updates") {
            HStack {
                if appUpdates.source == nil {
                    Link("Check GitHub Releases", destination: AppReleaseCheck.projectSource.releasesURL)
                        .buttonStyle(.bordered)
                        .help("Open public downloads in your browser. No GitHub account is required.")
                } else {
                    Button(appUpdates.busy ? "Checking…" : "Check for Updates") {
                        appUpdates.check(includeBetas: includeAppBetas)
                    }
                    .disabled(appUpdates.busy)
                    .accessibilityLabel("Check for MK Studio Upkeep updates").help("Check online for a newer MK Studio Upkeep release. Nothing is installed.")
                }
                if appUpdates.busy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { appUpdates.cancel() }.help("Stop this operation or close this view.")
                }
                if let page = appUpdates.releasePage {
                    Link("View release page", destination: page)
                }
            }
            Text(appUpdates.message)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let date = appUpdates.checkedAt {
                Text("Checked \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if appUpdates.source != nil {
                Toggle("Include beta releases", isOn: $includeAppBetas)
                    .disabled(appUpdates.busy)
                    .onChange(of: includeAppBetas) { _ in appUpdates.resetResult() }
                Text("Checks GitHub only when you ask. Like any website visit, GitHub sees your IP address; your inventory stays on this Mac. Downloads open in your browser and nothing installs itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
    }

    private func settingsRow<Control: View>(
        _ title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: StudioUpkeepDesign.Space.large) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: StudioUpkeepDesign.Space.regular)
            control()
        }
        .padding(.vertical, StudioUpkeepDesign.Space.medium)
    }

    private func scanToggle(
        _ title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        settingsRow(title, detail: detail) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func readOnlyRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, StudioUpkeepDesign.Space.medium)
    }

    private func note(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: StudioUpkeepDesign.Space.medium) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowDivider: some View {
        Divider()
    }

    private var accentPicker: some View {
        HStack(spacing: StudioUpkeepDesign.Space.medium) {
            ForEach(AppAccent.allCases) { option in
                Button {
                    accent = option.rawValue
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 16, height: 16)
                        .padding(4)
                        .overlay {
                            Circle()
                                .stroke(
                                    selectedAccent == option
                                        ? Color.primary
                                        : Color.secondary.opacity(0.25),
                                    lineWidth: selectedAccent == option ? 1.5 : 1
                                )
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel("\(option.title) accent")
                .accessibilityAddTraits(
                    selectedAccent == option ? .isSelected : []
                )
            }
        }
    }

    private var selectedAccent: AppAccent {
        AppAccent(rawValue: accent) ?? .monochrome
    }

    private func restoreRecommendedSettings() {
        showCategories = true
        showMenuBar = true
        showMenuBarAudio = true
        showDockIcon = true
        scanOnLaunch = false
        expandTechnicalDetails = false
        sidebarPosition = "left"
        appearance = AppAppearance.system.rawValue
        accent = AppAccent.monochrome.rawValue
        surfaceStyle = AppSurfaceStyle.glass.rawValue
        postScanDestination = PostScanDestination.smart.rawValue
        inventoryDensity = InventoryDensity.comfortable.rawValue
        scanDAWs = true
        scanAudioUnits = true
        scanVST3 = true
        scanVST2 = true
        scanCLAP = true
        restoredDefaults = true
    }
}
