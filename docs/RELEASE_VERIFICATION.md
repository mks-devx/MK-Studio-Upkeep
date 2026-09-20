# Release verification — 0.4.1, build 13

Reviewed 15 September 2026; release audit repeated 20 September 2026. This maintenance version isolates unreadable backup
records, guards storage totals, protects recovery copies during active removal,
refreshes manager discovery and corrects Tips and manual wording. The licence remains AGPL-3.0.

## Local verification

The 20 September audit rechecked the backup changes, publication files and Git
history. System-signature tests failed inside the restricted execution environment
and passed with normal macOS certificate access, without source changes. The only
Git author/committer email in reachable history is the public GitHub noreply identity.

- The complete release check passed: 286 Swift tests, with one opt-in Trash
  rehearsal skipped, five Python tests, native application-state checks and
  universal arm64/x86_64 packaging. A separate Trash-and-restore rehearsal passed
  against the unchanged build 12 core using disposable synthetic bundles;
  neighbouring test files remained unchanged.
- Three additional regressions reproduce and cover cleanup/restore attempts during
  an active removal, release of protection after success/failure, and honest
  reporting when removal status cannot be saved. The original race was reproduced
  before the fix using disposable bundles.
- Regressions reproduce and cover a damaged record beside a restorable backup,
  safe retention with unreadable records, overflowing stored sizes, and manager
  discovery after synthetic installation and removal.
- Publication-pattern, licence-consistency and reachable-history checks reported
  zero findings. These checks do not guarantee that every possible private value
  or ownership issue has been identified.
- Application-state regressions verify shared restore/cleanup activity, rejection
  of conflicting actions and progress cleanup after success or failure.
- Build 13 was launched with isolated preferences and no inventory scan. Restoring
  a disposable synthetic backup through Settings succeeded; recovered contents
  matched the fixture, the record gained a restore time, and the button changed
  to disabled “Already installed”. The recovery payload and neighbouring damaged
  record remained intact. “Show in Finder” revealed the isolated recovery folder.
- Backups settings were visually checked using macOS window capture, including
  readable-only counts and known storage size beside a damaged record. Shortened
  storage-button labels fit the settings window after the final rebuild. The native
  accessibility-inspection service crashed while inspecting this screen; the app
  remained running. Full accessibility verification remains incomplete.
- The app has no third-party Swift package dependency. Synthetic inventories and
  temporary storage exercise behaviour independently of a particular studio's
  installed products, paths or saved settings.

## Distribution checks

[GitHub Actions](https://github.com/mks-devx/MK-Studio-Upkeep/actions/runs/34766798742)
passed on macOS 15 Apple Silicon and Intel runners for source commit `4a6a487`,
including build, test, app-state, packaging and history checks for build 11.
Build 13 includes further source changes verified locally as described above;
those hosted results must not be presented as build 13 verification.

Signing, notarisation and mounted-installer verification remain pending before
this installer is published. Earlier release checks are recorded in their source
snapshots; they are not evidence that this installer has passed.

## Data and network boundaries

Scanning is local and does not execute plugin code. Reviewed website destinations
are matched on-device. Unknown plugins can still be inventoried; unrecognised DAWs
and managers may be missed. No current vendor-version catalogue is bundled.

The distributed app's own release action opens GitHub Releases in the browser.
The optional metadata reader in configured builds is separate from inventory and
runs only when requested. Neither action installs software. Bug-report previews
reach GitHub only after the user chooses to open the form.

The source, release descriptions and installer are publication material. Signing
credentials, notarisation logs, recovery archives, test homes and raw runtime
captures remain outside the repository. Publisher names and required notices are
intentional public attribution, not anonymous distribution.

## Limits

A temporary home/preferences test is not a clean macOS user account or a separate
computer. Physical Intel UI, the full macOS 13+ range, complete VoiceOver use and
broad DAW/plugin session compatibility remain unverified. Compiler support and
hosted tests cannot establish that every studio configuration works.

Removal handles eligible bundles only; it does not back up projects or external
settings and is not a complete vendor uninstaller. Unreadable backup records are
preserved for recovery rather than silently removed.

Technical checks are not legal clearance. Applicable publisher/contact notice
requirements remain a separate unresolved publication matter.
