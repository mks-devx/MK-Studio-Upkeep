# Privacy

**Your scan stays on your Mac. No tracking or inventory uploads.**

MK Studio Upkeep contains no analytics, advertising trackers or automatic crash-report uploader. It does not upload inventories, file paths, hardware names or activity readings. No account is required by the app.

## Local scanning and storage

Plugin and DAW scans read bundle metadata and executable headers without loading plugin code. They do not inspect your projects, presets, samples or licence contents. Hardware scanning reads Core Audio and Core MIDI properties and audio/MIDI driver metadata. It does not record audio, request serial numbers, probe firmware or change driver state.

The current inventory is held in memory. A local last-scan record stores product names, vendors, versions and opaque identifiers. Preferences, additional scan folders and app-release cache data remain on your Mac. Older installations may retain catalogue cache files; the current app does not load or import those catalogues.

On-demand activity inspection reads process names and CPU/memory use locally. These readings are not included in inventory exports. Cache inspection reads supported locations and file metadata without deleting caches.

## Websites and software managers

Scanning makes no network requests. Official destinations are matched on-device against a reviewed directory containing developer identities and links, not current plugin versions. The app does not run an internet search, fetch plugin releases or send product names to a lookup service. Unrecognised products still appear in the local inventory; their official website may remain unidentified.

Choosing a website opens your browser. Choosing an installed software manager opens that application after signature checks. The destination's normal privacy policy and connection behaviour apply. No inventory, installed version or local path is appended to these actions. Bundle-declared website/feed addresses remain local technical evidence and are not contacted during scanning.

## MK Studio Upkeep updates

The manual **Check for Updates** action in Settings → About concerns this app only. Private builds open GitHub Releases in the browser. A build configured for a public release repository can contact `api.github.com` to read release metadata. It sends no plugin inventory, file paths, credentials or machine profile and does not run automatically. GitHub receives normal connection information, including the connection's public IP address.

## Reports and screenshots

**Report a bug** prepares a preview locally. Optional diagnostics are off by default and include app/macOS/processor information and aggregate scan counts. Raw logs, paths and product lists are not attached. Your own description is included as written.

Opening the GitHub report form places the preview in its URL, which may remain in browser history. You submit the issue yourself. Copying a report uses the system clipboard; clipboard managers and system clipboard sharing may retain it. Nothing is submitted automatically.

Inventory exports can contain installed product names, versions and paths. Device names may also contain personal text. Review all reports and screenshots before sharing. The app does not generate or upload a support archive. macOS may retain its own diagnostics under your system settings.

## Optional removal

Removal review searches configured software locations and common Library locations for exact bundle-identity associations. Associated support files are preserved. Eligible bundle contents are enumerated and filesystem metadata is checked again before removal; this information stays local.

Only explicitly selected and confirmed eligible software bundles move to macOS Trash. Content stored inside a selected bundle moves with it. External creative content, preferences, support folders and licences are not selected. Driver-file removal is disabled.

## Removing local app data

Restoring defaults in Settings changes presentation and scan options; it is not a data-erasure action. To remove all local app data, quit the app, inspect its preferences and its Studio Upkeep Application Support folder, then remove only the app's own data using macOS file/preference management. Audio software, projects and vendor-manager data do not need to be removed.
