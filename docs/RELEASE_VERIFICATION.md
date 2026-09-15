# Release verification — 0.4.1, build 12

Reviewed 15 September 2026. This maintenance version isolates unreadable backup
records, guards storage totals, protects recovery copies during active removal,
refreshes manager discovery and corrects Tips and manual wording. The licence remains AGPL-3.0.

## Local verification

- The complete release check passed: 286 Swift tests, with one opt-in Trash
  rehearsal skipped, five Python tests, native application-state checks and
  universal arm64/x86_64 packaging. The skipped Trash-and-restore rehearsal then
  passed separately using disposable synthetic bundles; neighbouring test files
  remained unchanged.
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
- Build 12 launches and opens General settings on Apple Silicon. Backups visual
  inspection remains incomplete: the native UI-inspection service crashes when
  reading that screen. Its crash report identifies the inspection service; the
  application process remains running. Earlier build 11 first-run/manual checks
  do not establish full visual verification of the revised backup controls.
- The app has no third-party Swift package dependency. Synthetic inventories and
  temporary storage exercise behaviour independently of a particular studio's
  installed products, paths or saved settings.

## Distribution checks

[GitHub Actions](https://github.com/mks-devx/MK-Studio-Upkeep/actions/runs/34766798742)
passed on macOS 15 Apple Silicon and Intel runners for source commit `4a6a487`,
including build, test, app-state, packaging and history checks for build 11.
Build 12 includes further source changes verified locally as described above;
those hosted results must not be presented as build 12 verification.

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
