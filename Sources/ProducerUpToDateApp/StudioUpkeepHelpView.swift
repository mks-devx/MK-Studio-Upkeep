// SPDX-License-Identifier: BUSL-1.1
import SwiftUI

struct StudioUpkeepHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ManualSection.overview

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: StudioUpkeepDesign.Space.medium) {
                AppIconView(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MK Studio Upkeep Manual")
                        .font(.title2.weight(.semibold))
                    Text("Every result explained, before you act.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(
                .horizontal,
                StudioUpkeepDesign.Space.large
            )
            .padding(.vertical, StudioUpkeepDesign.Space.regular)

            Divider()

            NavigationSplitView {
                List(ManualSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(
                    min: 190,
                    ideal: 210,
                    max: 240
                )
            } detail: {
                ManualArticle(section: selection)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 840, idealWidth: 940, minHeight: 650, idealHeight: 720)
        .studioCanvasBackground()
    }
}

private enum ManualSection: String, CaseIterable, Identifiable {
    case overview
    case macStatus
    case hardware
    case scanning
    case results
    case updates
    case appleSilicon
    case uninstall
    case settings
    case privacy
    case shortcuts
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
        case .macStatus:
            return "Mac Status & Storage"
        case .hardware:
            return "Hardware & Managers"
        case .scanning:
            return "Scanning"
        case .results:
            return "Understanding Results"
        case .updates:
            return "Plugin & DAW Updates"
        case .appleSilicon:
            return "Apple Silicon"
        case .uninstall:
            return "Uninstall Review"
        case .settings:
            return "Settings"
        case .privacy:
            return "Privacy & Evidence"
        case .shortcuts:
            return "Keyboard Shortcuts"
        case .troubleshooting:
            return "Troubleshooting"
        }
    }

    var symbol: String {
        switch self {
        case .overview:
            return "list.bullet.rectangle"
        case .macStatus:
            return "desktopcomputer"
        case .hardware:
            return "hifispeaker"
        case .scanning:
            return "magnifyingglass"
        case .results:
            return "heart.text.square"
        case .updates:
            return "arrow.down.circle"
        case .appleSilicon:
            return "cpu"
        case .uninstall:
            return "trash"
        case .settings:
            return "switch.2"
        case .privacy:
            return "lock.shield"
        case .shortcuts:
            return "keyboard"
        case .troubleshooting:
            return "wrench.and.screwdriver"
        }
    }
}

private struct ManualArticle: View {
    let section: ManualSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.large) {
                VStack(alignment: .leading, spacing: StudioUpkeepDesign.Space.small) {
                    Label(section.title, systemImage: section.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(introduction)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                ForEach(topics) { topic in
                    VStack(
                        alignment: .leading,
                        spacing: StudioUpkeepDesign.Space.small
                    ) {
                        Text(topic.title)
                            .font(.headline)
                        Text(topic.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(StudioUpkeepDesign.Space.xLarge)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .studioCanvasBackground()
    }

    private var introduction: String {
        switch section {
        case .overview:
            return "A clear picture of the music software on your Mac, with every claim tied to a source and a date."
        case .macStatus:
            return "Read local system and storage information without changing your audio setup."
        case .hardware:
            return "Find audio devices, MIDI entries, drivers and recognised vendor managers."
        case .scanning:
            return "A scan reads the metadata inside each plugin and app. It never opens or runs a plugin."
        case .results:
            return "Review groups local findings; Your studio shows the detected software and hardware."
        case .updates:
            return "Open a developer website or installed manager to check releases yourself. Scanning checks installed files only."
        case .appleSilicon:
            return "Intel-only findings describe installed files. Ask the developer about native installers for the exact product and format."
        case .uninstall:
            return "Removal is preview first, exact identity only, and goes to the Trash so you can undo it."
        case .settings:
            return "Choose what is scanned and how results look. The evidence rules cannot be loosened."
        case .privacy:
            return "Your inventory stays on your Mac. Anything that comes from outside carries its source and date."
        case .shortcuts:
            return "Move around and rescan without leaving the keyboard."
        case .troubleshooting:
            return "Most surprises come from plugin metadata, mixed formats or protected folders."
        }
    }

    private var topics: [ManualTopic] {
        switch section {
        case .overview:
            return [
                topic("What is scanned", "Audio Unit, VST3, VST2 and CLAP plugins in the system and user Library folders, any folders you add, and recognised DAW applications."),
                topic("What you learn", "Installed versions, formats, processor architecture and local compatibility findings. Reviewed directory links lead to developer websites. Latest releases, newer editions and native installers are not checked."),
                topic("Hardware and drivers", "Hardware lists audio interfaces, outputs and MIDI devices. Drivers lists installed audio and MIDI driver software. Each driver entry says what it is, who makes it and where its updates come from. Each device names the vendor app or page that delivers firmware. MK Studio Upkeep never reads firmware versions itself."),
                topic("What is never assumed", "Missing information is never treated as proof that a product is current or compatible. Unknown websites remain unidentified.")
            ]
        case .macStatus:
            return [
                topic("This Mac", "Overview shows macOS, time since the last restart, thermal state, Low Power Mode and free space on the volume containing your home folder. Refresh updates these readings. Time since restart alone is not a reason to interrupt a session."),
                topic("Measure software size", "Choose Measure software size for the scanned plugin and DAW bundles. Hidden files are included, links are not followed, and hard-linked files count once within each measurement. External sample libraries and projects are excluded. These are logical file sizes, not guaranteed space recovered by uninstalling."),
                topic("Partial measurements", "Not measured means you have not measured this inventory. At least marks an incomplete measurement. Cancel keeps the previous completed result; a new inventory clears the old sizes."),
                topic("Cache inspection", "Cache inspection measures supported locations without removing files. Bitwig and Reason have documented additional locations; FL Studio and Maschine use standard cache folders only. Browser databases and favourites are preserved. Open DAW coverage and precautions for limitations and vendor instructions."),
                topic("Memory", "Overview shows estimated RAM usage, memory pressure, compressed memory and swap used. Refresh memory takes a new local snapshot. Estimates may differ from Activity Monitor; high usage or swap alone does not prove audio problems."),
                topic("Before a session", "Scan, then test the actual session in your DAW with the intended interface and MIDI inputs. Check monitoring and the busiest passage. Overview shows free space on the home volume; check your recording drive separately. A scan does not certify playback stability."),
                topic("Before changing software", "Our recommendation: back up first, check the official requirements and test a copy of a representative session after an update. Check playback, recording, automation, export and save/reopen. MK Studio Upkeep does not know which sessions need a plugin."),
                topic("Music-production tips", "Open Tips for recording buffers, playback underruns, loaded-instrument memory use and studio maintenance. Each tip names its scope and links to official documentation. These are manual checks; the app does not optimise settings."),
                topic("Audio stability", "Check activity shows separate top-five lists for recent CPU usage and resident memory on demand. Resident memory can include shared pages and differs from Activity Monitor’s Memory column. The average covers up to a minute and can exceed 100%; it does not prove audio dropouts. Process names stay on this Mac. Activity Monitor and Audio MIDI Setup open the system tools. The dashboard does not measure audio dropouts, MIDI clock jitter or cache health, and does not change system settings. Check your DAW for its actual audio configuration.")
            ]
        case .hardware:
            return [
                topic("Browse groups", "Open Hardware for audio and MIDI devices, or Drivers for installed driver software. Hardware’s Show control filters audio or MIDI entries. Search narrows the chosen group. Built-in and virtual audio devices may appear alongside external equipment."),
                topic("Device settings", "Select an audio device for its reported sample rate and buffer frames, when available. These are Core Audio readings at scan time. Your DAW may request a different buffer. Firmware versions and MIDI clock quality are not measured."),
                topic("Drivers", "Read the maker’s update or removal route before acting. A red Don’t delete this mark removes the removal control. Kernel and system extensions and Apple components require their designated procedure. Device associations are guidance, not proof that equipment is unused."),
                topic("Saved MIDI entries", "Offline entries can remain after unplugging equipment. Review removal carefully: forgetting an entry loses its custom name and port setup. Connected and system entries are protected. A saved entry does not establish whether you use that device."),
                topic("Plugin Managers", "The sidebar lists recognised software managers, licence tools and hardware managers. Refresh after installation. A suggested manager does not prove it installed a product or supports its uninstall. Before launch, review the publisher shown in the confirmation; cancel if unexpected. Accounts, passwords and entitlements are not scanned.")
            ]
        case .scanning:
            return [
                topic("Start a scan", "Choose Scan This Mac on the welcome screen, or press Shift-Command-R. During a rescan the previous inventory stays visible."),
                topic("Changes between scans", "Open Scan details to review products that appeared, disappeared or changed version since a comparable completed scan. Names and versions stay on this Mac. Changed scan scope or incomplete coverage prevents comparison."),
                topic("Change what is scanned", "Settings › Scanning lets you switch plugin formats and DAW scanning on or off and add plugin folders. Changes apply on the next scan."),
                topic("Cancel safely", "Cancel Scan stops the current pass. Nothing on disk changes, and the earlier inventory remains.")
            ]
        case .results:
            return [
                topic("Your studio", "Plugins, DAWs, Software Managers, Hardware and Drivers show what was detected on this Mac."),
                topic("Review", "Choose a finding in the sidebar to review compatibility, different versions, multiple copies or related editions. Intel-only copies includes products with an Intel-only installed file. Choose Plugins to return to all products. Cache inspection is under Maintenance."),
                topic("Update options", "Select a product to open its developer app or website, where known. A suggested manager does not prove you installed the product with it or that an update exists.")
            ]
        case .updates:
            return [
                topic("Installed versions", "Scanning reads the files on your Mac. It does not check online and does not compare with a saved list of release versions."),
                topic("Developer websites", "Select a plugin or DAW to open its reviewed developer website or installed software manager. Matching is local. Unknown websites stay unidentified; current releases are not fetched or compared."),
                topic("Other products", "Use the developer’s app, website or App Store. If no website is identified, find the developer independently. After installing an update yourself, rescan to read the installed version."),
                topic("Before installing", "Check requirements, licence eligibility and project compatibility with the developer. A release listing does not establish compatibility or entitlement."),
                topic("Independent software", "Product names identify your software and belong to their owners. MK Studio Upkeep is not affiliated with or endorsed by those developers.")
            ]
        case .appleSilicon:
            return [
                topic("Intel-only copies", "This filter shows products with at least one Intel-only file. Other formats of the same product may contain native code. Installed copies show each format separately."),
                topic("Native updates", "Ask the developer whether a native installer exists for your exact product, version and format. The scanner inspects installed code; it cannot establish host compatibility.")
            ]
        case .uninstall:
            return [
                topic("Right-click actions", "Right-click a plugin, DAW or update row for Show in Finder or Review uninstall…. Revealing a location does not launch the software. Driver rows have a separate removal review or instructions."),
                topic("Deep discovery", "The review searches common system and current-user Applications and Library locations, configured plugin folders and hidden entries. It uses identifiers rather than a fixed list of products. Exact-ID software copies may join the unchecked preview after safety checks; name matches never authorise removal."),
                topic("Limits", "Associated-file discovery is bounded to 200,000 entries and limited depth. Warnings mean more files may exist, including in other accounts or locations. Each bundle preview inspects up to 250,000 entries and displays the first 200 names. A failed bundle preview prevents removal; related support files stay protected."),
                topic("Confirm removal", "Close DAWs and plugin hosts, select only the bundles you intend to remove, and acknowledge the review. Hold the final button for five seconds, then release. Releasing early or pressing Escape cancels the hold. Assistive activation opens a separate dialog: wait five seconds, then choose Confirm. Cancel makes no changes. No items are selected by default."),
                topic("Settings stay on your Mac", "Deep review lists identified settings and related files with their original locations and individual Show in Finder actions. Copy kept locations copies the paths and search warnings. These files are not selected for removal or backed up. No results does not prove no settings exist. Use the vendor’s procedure for a full reset."),
                topic("Review every file", "Removal is experimental. Choose Review Uninstall Files, then tick the bundles yourself; nothing is preselected. The preview is frozen, and each item is checked again before it moves. Unselected preferences and support folders stay."),
                topic("Your work is kept", "Presets, samples, projects, licences and shared folders outside the bundle are never selected. Anything saved inside a selected bundle moves with it, so back it up first. Full removal may need the vendor’s uninstaller."),
                topic("Undo", "Approved items go to the Trash. Close your DAWs first, and don’t empty the Trash until your sessions open correctly.")
            ]
        case .settings:
            return [
                topic("General", "Scan on launch, the section shown after a scan, Dock and menu-bar visibility, menu-bar audio, appearance, accent colour, list spacing and optional plugin categories. Categories use declared metadata: Instrument, Audio Effect, MIDI Effect or Uncategorised. Supported VST3 metadata can add roles such as EQ or Delay."),
                topic("Scanning", "Plugin formats, DAW scanning and extra plugin folders."),
                topic("Evidence", "Privacy information and the technical-details preference. Changing this preference updates open plugin, DAW and driver views."),
                topic("Dock and menu bar", "At least one icon stays visible. The menu offers scanning, settings and window controls."),
                topic("MK Studio Upkeep updates", "Check for Updates in About checks MK Studio Upkeep itself. A configured build opens published releases in your browser; it does not install them. If no release destination is configured, the app says so."),
                topic("Restore defaults", "Restore presentation and scan defaults is in General. It resets appearance, visibility, details and scan choices. Additional plugin folders and app-update preferences are kept.")
            ]
        case .privacy:
            return [
                topic("Local inventory", "No analytics or automatic inventory uploads. Scanning is local. You choose whether to export or share information."),
                topic("Report a bug", "Use Help → Report a bug. Diagnostics are optional and the preview shows what will be shared. Opening the form sends the preview to GitHub; you submit the issue there. A GitHub account with repository access is required."),
                topic("Developer links", "Developer links open only when chosen. The destination receives a normal browser request. Plugin paths and the rest of your inventory are not added."),
                topic("App update check", "The optional MK Studio Upkeep update check contacts GitHub only when requested. Like any website visit, the site sees your IP address; your inventory stays on this Mac."),
                topic("No commercial influence", "Partnerships or offers never affect update status, ordering or confidence.")
            ]
        case .shortcuts:
            return [
                topic("Command-1", "Open Plugins."),
                topic("Command-2", "Open DAWs."),
                topic("Command-3", "Open Software Managers."),
                topic("Command-4", "Open Needs Attention."),
                topic("Shift-Command-R", "Scan this Mac again."),
                topic("Command-?", "Open this manual."),
                topic("Command-,", "Open Settings.")
            ]
        case .troubleshooting:
            return [
                topic("A product is missing", "Check that its format is enabled in Settings and that it lives in a scanned folder. Add the folder if needed, then rescan."),
                topic("Checking a release", "Check current releases with the developer. Scanning does not compare release versions or establish that your software is current."),
                topic("A driver you don’t recognise", "Open it in Drivers. The “What this is” section names the maker and its purpose. Apple’s own components are marked as part of macOS. Check with the maker before removing anything."),
                topic("Intel-only after reinstall", "Confirm the vendor installer includes a native build for that exact format. Some vendors keep VST2 Intel-only while AU and VST3 are native."),
                topic("Uninstall cannot move a file", "Close all DAWs and plugin hosts, then check the file’s permissions. Eligible system-root moves use Finder, which may request administrator authentication. Home-folder moves do not use that route. Changed files require a new review. A failure may leave a partial result: inspect it before retrying, and never bypass protection.")
            ]
        }
    }

    private func topic(_ title: String, _ body: String) -> ManualTopic {
        ManualTopic(title: title, body: body)
    }
}

private struct ManualTopic: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}
