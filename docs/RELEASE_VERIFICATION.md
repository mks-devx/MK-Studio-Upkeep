# Release verification — 0.2.0, build 8

Reviewed 8 September 2026. Public distribution uses a clean source snapshot and
the verified version 0.2.0 installer. The release focuses on local inventory and official developer destinations; automatic plugin/DAW release checks are not part of the app.

## Local checks

- `STUDIO_UPKEEP_TRASH_REHEARSAL=1 ./scripts/check.sh`: **321 Swift tests, 8 Python tests, no failures**. The disposable bundle Trash/restore rehearsal passed; neighbouring synthetic content was preserved.
- Application-state regressions passed: navigation/filter resets, failed-rescan notices with retained results, unknown MIDI availability, cancelled/stale detail reads and accurate empty Review states. Negative-control copies confirmed the regressions detect removed safeguards.
- Publication-pattern, licence-consistency and packaged-file audits: zero findings. Markdown links in the distribution snapshot were checked.
- Universal release build completed for arm64 and x86_64, targeting macOS 13 and later.
- Native confirmation tests passed eight mouse/Space cases plus assistive cancellation, early rejection, delayed confirmation and disabled-state checks. Callbacks were harmless; they did not remove installed software.

The build retains a deprecated Launch Services discovery call. It is used only to locate candidate manager apps; signature and publisher review still precede opening. No build errors remain.

## Native interface and installer

Checked on Apple Silicon with macOS 26.5.2: launch, local scan completion, Review navigation and empty results, Settings sections, About version/build, top-navigation parity, light/dark appearance, live technical-detail changes, and separate hardware/driver views. Protected drivers retained instructions instead of a generic removal action. Presentation preferences used during review were restored.

The app copied from the completed installer launched and scanned successfully. The installer contains the app, installation instructions and an Applications shortcut. Both app and DMG were signed with the established Developer ID publisher identity, accepted by Apple notarisation and stapled. Strict signature checks, ticket validation, Gatekeeper assessments and disk-image integrity checks passed. No real plugins, drivers or studio content were removed during this review.

## Hosted checks

The application source passed macOS 15 Apple Silicon and Intel CI before public
publication. Each job ran the core suite, application-state checks, universal
packaging and publication-history audit. The opt-in Trash rehearsal ran locally;
hosted jobs skipped it. Current public runs appear under [Actions](https://github.com/mks-devx/MK-Studio-Upkeep/actions/workflows/ci.yml).

The public source snapshot also removes the unused release catalogue and uses
synthetic catalogue fixtures. That cleanup passed 320 Swift tests (one opt-in
Trash rehearsal skipped), 9 Python tests, application-state checks, universal
packaging, and Apple Silicon and Intel CI. It does not change the released app's
local inventory or website-link behaviour. The signed installer is the original
verified 0.2.0 build; it has not been rebuilt from the cleaned source snapshot.

## GitHub and privacy review

Reachable repository history, tags, current files, release metadata and the previous installer were inspected. A separate post-upload scan covered the new source blobs. No confirmed credentials, private inventories, maintainer home paths or personal screenshots were found. Outdated UI images and internal historical notes are excluded from the new source snapshot; development history and beta tags are not part of the public repository.

CI is restricted to GitHub-owned Actions and uses a pinned checkout action with read-only repository permissions. No secrets or inventory fixtures were uploaded. The normal publisher identity is visible in Developer ID signatures.

Automated pattern checks do not establish the absence of all private data.
They cannot inspect third-party copies. GitHub private vulnerability reporting
is the security-reporting route; see [Security](../SECURITY.md).

## Remaining boundaries

Full VoiceOver, clean-account/browser-quarantine installation, physical Intel UI operation and the full macOS 13+ range have not been validated. Hosted Intel tests are not physical studio or audio-host testing. Website/DAW/manager recognition is limited; unknown plugins remain locally inventoried. Architecture is not a guarantee of DAW compatibility. Optional software removal remains experimental.

Signing, automated audits and a stable release label do not establish universal compatibility, absence of vulnerabilities or professional legal clearance.
