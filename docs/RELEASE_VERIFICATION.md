# Release verification — 0.3.0, build 9

Reviewed 9 September 2026. Version 0.3.0 is the first MPL-2.0 release. It
focuses on private local inventory, installed-copy comparisons, architecture
findings and reviewed official developer destinations. It does not claim to
check current plugin or DAW releases.

## Source and local checks

- Release source commit: `e84cb608fb2d6b86aa5e1698f5efcbea22d36f52`.
- `STUDIO_UPKEEP_TRASH_REHEARSAL=1 APP_STATE_SCRATCH=../final-release-app-state ./scripts/check.sh`: **327 Swift tests and 14 Python tests, no failures**. One network opt-in test was skipped. The disposable Trash/restore rehearsal passed without using installed software.
- Publication-pattern, licence-consistency, packaged-file and application-state audits reported zero findings.
- The release build completed as a universal arm64/x86_64 app targeting macOS 13 and later.
- The only build warning is the existing deprecated Launch Services discovery call used to locate candidate software-manager apps. Candidate apps still require signature and publisher validation before opening.

## Interface review

Dark and light appearances were checked with a fictional inventory. The review
covered compact result headers, consistent filters, sidebar colour, empty
states, installed versions, different-version findings, settings and About.
Newer-edition suggestions and automatic plugin-update wording were removed.
Official destinations remain clearly separate from manual browser search.

The exact installed build launched on Apple Silicon with macOS 26.5.2 and
displayed the final first-run screen. Its process resolved to
`/Applications/MK Studio Upkeep.app`. No real software was removed during the
runtime check.

## Signing and installer

The app and disk image were signed with the established Developer ID identity,
accepted by Apple notarisation and stapled. Strict signature validation,
Gatekeeper assessment, ticket validation, disk-image integrity and the release
checksum passed. The mounted installer contains version 0.3.0 build 9 with both
arm64 and x86_64 executable slices and the expected MPL, privacy and third-party
notices.

Release disk image SHA-256:

```text
50a6426d955d99dc69ac0f4efe28c4335e0c456eb2bf6bfdfed126b3edb410ab
```

Only the disk image and `SHA256SUMS.txt` are public release assets.
Notarisation records, test inventories, screenshots containing local data,
installed-app backups and signing material remain private.

## Hosted checks

The release is published only after the GitHub-hosted Apple Silicon and Intel
jobs pass. Each job runs the core suite, application-state checks, universal
packaging and publication-history audit. The opt-in Trash rehearsal remains a
local check. Current runs appear under
[Actions](https://github.com/mks-devx/MK-Studio-Upkeep/actions/workflows/ci.yml).

## GitHub and privacy review

The public file set, reachable history, tags, workflow permissions, release
metadata and assets were reviewed. Automated publication checks found no
credentials, personal paths, private inventories, real studio screenshots or
third-party plugin binaries. Private development history and beta installers
remain excluded. Automated pattern checks cannot prove that every form of
private data is absent.

CI uses GitHub-owned Actions with read-only repository permissions. GitHub
private vulnerability reporting is the security-reporting route; see
[Security](../SECURITY.md).

## Remaining boundaries

Physical Intel operation, the complete macOS 13+ range, broad DAW/plugin host
compatibility, full VoiceOver use and a clean-account installation were not
validated. Website, DAW and software-manager recognition remains intentionally
limited; unknown products are still inventoried. Architecture does not prove
DAW compatibility. Optional removal remains experimental because the app can
identify and move reviewed bundles to Trash, but it cannot guarantee a complete
vendor-specific uninstall.

This engineering review is not professional legal advice or a legal clearance.
Open-source licensing does not remove any publisher, privacy or trademark
obligations that may apply in a particular jurisdiction.
