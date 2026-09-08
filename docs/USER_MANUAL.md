# MK Studio Upkeep user manual

MK Studio Upkeep inventories installed audio software and helps you review local
findings. It points you to developer websites and software managers; it does not
check or install current plugin or DAW releases.

## Start a scan

Choose **Scan This Mac** on the welcome screen, or **Rescan** above the inventory.
Scanning reads files without loading plugin code or changing audio software.
Cancel stops the current scan; an earlier completed inventory remains available.

Standard locations include the system and current user's Audio Units, VST3, VST2
and CLAP folders. In **Settings → Scanning**, choose formats, include recognised
DAWs, or add extra plugin folders. DAW discovery uses application folders separately.
Adding a plugin folder does not expand DAW discovery.

An unfamiliar plugin can still appear without an entry in the website directory.
Developer names, versions or architectures that cannot be determined stay unknown.
DAWs and software managers require recognised application identities; an unlisted
application may be missed.

## Navigate the inventory

| View | Contents |
| --- | --- |
| Overview | Scan summary and optional local system/activity information. |
| Plugins | Installed plugin products and their individual files. |
| DAWs | Recognised DAW applications; separate installations remain separate. |
| Software Managers | Recognised product managers and licence tools. |
| Hardware | Audio devices and MIDI entries reported by macOS, including virtual devices. |
| Drivers | Installed audio and MIDI driver software. |
| Review | Local findings described below. |
| Cache inspection | Read-only sizes for recognised cache locations. |
| Tips | Practical audio guidance and source links. |

Search narrows the current inventory. The count above the table follows active
filters; sidebar counts describe the full inventory for that finding. Choose
**Plugins** to return to the complete plugin list.

Above plugin results, use the category and architecture/issue controls to narrow
the list. **More** contains export, scan details, an explanation of the results,
and **Show plugin categories**. Hiding categories also clears the category filter.
Review findings live in the navigation, not in a separate filter dropdown.

## Understand Review findings

| Finding | What it establishes |
| --- | --- |
| Needs Attention | Local scanner findings, including unreadable or incompatible files and Intel-only copies. |
| Intel-only copies | At least one installed file has Intel code without Apple Silicon code. Other copies may be native. |
| Cannot run on this Mac | A detected file is 32-bit-only, or Apple Silicon-only on an Intel Mac. |
| Different versions | Installed copies report different version values. This is not an online update result. |
| Multiple copies | The same format appears in more than one distinct installed location. Different formats are not duplicates. |
| Related editions | Product names, developer identity and installed major versions suggest related editions. These remain separate products. |
| Newer editions | A narrowly reviewed record identifies a newer edition. Records expire; no live release or price lookup occurs. |

**Old does not mean broken.** File age alone does not establish compatibility,
discontinued support or whether a plugin works in a session. No general list of
obsolete or unsupported products is inferred from dates.

An Intel-only plugin may need Rosetta or a compatible host mode on Apple Silicon.
Architecture does not establish operating-system, DAW, format or dependency
support. Check the developer's requirements before making changes.

## Inspect a product

Select a row to see its name, installed version, architecture and relevant findings.
The detail view offers a reviewed developer website and, when available, a matching
installed software manager. Unknown websites remain unidentified.

Expand **Installed files** to compare each format, version and location. Two copies
in different locations are kept separate. **Show file** reveals the file in Finder.
**Technical details** contains raw metadata, identity and signature information.
Missing or conflicting information is not treated as a confirmed match.

Related-edition links open the other installed product. Keep editions needed by
older sessions; a newer edition does not make the old one safe to remove.

## Where to check for updates

Choose **Open developer website** or **Open [manager]**. The directory contains
reviewed identifiers and official destinations, not a list of supposedly current
versions. A developer-wide downloads or support page may serve several products.
Matching takes place on your Mac and makes no online request during scanning.

Opening a website uses your browser. Opening a manager checks its publisher
through the app's signature review and hands control to that application. A manager
suggestion does not prove it installed the product, owns its licence or supports
uninstalling it. Browser and manager privacy policies apply.

Download and install updates through the developer, then rescan. The app does not
store vendor credentials or decide licence eligibility. A newer edition may require
an additional purchase; check the official page and your account.

## Hardware and drivers

Hardware shows Core Audio devices and Core MIDI entries. Built-in outputs,
aggregate/virtual devices and saved MIDI entries can appear alongside external
equipment. MIDI availability is not proof of a physical connection; unknown status
stays unknown. Firmware versions are not read or compared.

Driver details identify the software and its maker, when known, and provide
reviewed update or removal guidance. A **Don't delete this** protection identifies
system components or protected dependencies. Driver files cannot be removed by
MK Studio Upkeep; use the developer's instructions.

Saved, disconnected MIDI entries have a separate review flow. Removing one forgets
its saved configuration; reconnecting the device may recreate an entry and require
setup. Connected, system-owned and uncertain entries stay protected.

## Settings

- **General:** startup and post-scan behaviour, appearance, navigation position,
  inventory density, and app/menu-bar visibility.
- **Scanning:** enabled plugin formats, recognised DAW scanning and additional folders.
- **Evidence:** technical-detail preferences and the local-data/source policy.
- **About:** version/build, documentation, licence information and the app's own releases.

Presentation choices do not alter installed software. Restoring presentation and
scan defaults keeps additional plugin folders; review the reset description first.

MK Studio Upkeep's own update action is separate from plugin information. For a
release-page configuration it opens GitHub Releases in your browser. A configured
public release check contacts GitHub only when requested. Optional beta releases
are separate from normal releases. Nothing is installed automatically.

## Scan details and limitations

The timestamp records the last completed scan. If a rescan fails, previous results
remain available with a failure notice; they are not a newly completed scan.

Plugin scanning reports unreadable locations. Missing optional standard folders
are described without treating their absence as missing software. Symbolic-link
bundles, AAX, AUv3 and devices internal to a DAW are outside the plugin scan scope.

The DAW search has depth and item limits. **Folders beyond the search depth** lists
deeply nested locations as scope notes; a DAW stored there may be missing. Access
failures and searches stopped by the item limit remain **Search problems** and
produce a sidebar warning. Rescanning does not extend these limits.

Changes since the previous scan are available inside Scan details when present.
They compare locally recorded inventories, not current releases on the internet.

## Export and support

Choose **More → Export inventory** to save a CSV or text report locally. Reports
can contain product names and paths. Check the file before sharing it.

Choose **Help → Report a bug…** to prepare a local preview. Optional diagnostics
are off by default.
Opening the GitHub form sends that preview in the browser URL; you submit the issue
yourself. Remove personal names, paths, account details and private project content.
Never share credentials, licences or third-party plugin binaries.

Bug reports and fixes are best-effort. General questions and individual setup
support are not offered; please do not use email or social media for support.
For security vulnerabilities, follow the [security policy](../SECURITY.md).

## Optional removal

Software removal is experimental and separate from scanning. Read the file list,
select eligible bundles, close hosts and acknowledge the review before confirming.
The final control requires a five-second hold and release with the mouse or Space key.
Assistive activation opens a separate confirmation with the same delay. Cancel changes nothing.

Only reviewed software bundles move to Trash. External settings, support folders,
projects, recordings, presets, samples and licence data are kept. Content inside a
selected bundle moves with it. A product may need its developer's uninstaller for
complete removal; a matching filename never establishes ownership.

The app rechecks the selected files before moving them. Changed or unsafe files
are rejected. A partial failure reports what moved and stops remaining work. Keep
Trash intact until you have checked your sessions. Restore from Trash or backup if
needed; this app does not provide an automatic restore service.

Cache inspection never deletes files. Driver-file removal is disabled.
See [Removal boundaries](UNINSTALL_REVIEW.md) for the detailed safeguards.

## Further information

[Installation](INSTALLATION.md) · [Platform support](PLATFORM_SUPPORT.md) ·
[Privacy](../PRIVACY.md) · [Support](../SUPPORT.md) · [Security](../SECURITY.md)
