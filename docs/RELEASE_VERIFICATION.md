# Release verification — 0.4.0, build 10

Reviewed 13 September 2026. Version 0.4.0 adds protected local removal backups,
restore history and explicit retention controls. It changes the current source
licence to AGPL-3.0. The app remains a local inventory and official-destination
tool; it does not claim to check current plugin or DAW releases.

## Source and local checks

- The publication-pattern and licence-consistency audits reported zero findings.
  The licence audit checked 205 source and script files.
- All 341 Swift tests completed in the release gate, and the suite also completed
  under AddressSanitizer and ThreadSanitizer without failures or sanitizer reports.
  Fourteen Python collector tests, native application-state checks and universal
  packaging also passed.
- Removal-backup regressions verify complete-copy-before-remove behaviour,
  fingerprint checks, collision-safe restore, retention, owner-only metadata
  permissions and rejection of symbolic-link storage roots.
- The release build compiles with warnings treated as errors and packages arm64
  and x86_64 code targeting macOS 13 and later.
- The opt-in Trash/restore rehearsal uses disposable synthetic bundles only; it
  does not touch installed audio software.

## Interface review

Dark and light appearances were checked with an isolated presentation host and
a fictional eight-product inventory. The review covered the layouts previously
reported as crowded: section titles, result counts, filter controls, Review
navigation, installed-copy details and empty states. Hardware and Drivers remain
separate. Settings exposes backup creation, 7/30/90-day retention, indefinite
retention, cleanup and restore history.

The current screenshots come from the 0.4.0 application-view source. The capture
host does not scan this Mac or contact the internet. Product names, paths, versions,
counts and dates are synthetic; capture metadata was removed and the images were
converted to sRGB.

## Network and privacy boundary

Normal scans make no network request. Developer destinations are matched locally
from a small reviewed directory that contains identifiers, official links and
review dates, but no current-version list. Unknown software is still inventoried.
The separate **Check GitHub Releases** action concerns MK Studio Upkeep only and
opens the release page in the distributed build.

The release review requested all 83 unique HTTPS destinations in the plugin,
manager, DAW, hardware and driver directories without inventory data. Seventy-six
returned successfully. Seven official support pages rejected automated access with
HTTP 403 and were cross-checked against official references or browser-indexed
official pages; those responses are not presented as proof of browser availability.
Five obsolete links were replaced with current official pages.

The public file set and reachable Git history are checked for credentials,
personal paths, private inventories, real studio screenshots and third-party
plugin binaries. The app contains no telemetry or automatic crash uploader.
Backup manifests containing original paths stay local and use owner-only file
permissions. The report preview is local until the user chooses to open GitHub;
the privacy notice explains the resulting public or private GitHub processing.

## Signing and installer

The distribution app and disk image must be signed with Developer ID, accepted by
Apple notarisation and stapled. Strict signature validation, Gatekeeper assessment,
ticket validation, image integrity, mounted-app inspection and the published
checksum must pass for the exact release commit. Only the disk image and
`SHA256SUMS.txt` are public assets; notarisation records, test data, capture tools,
installed-app backups and signing material remain private.

## Hosted checks

GitHub Actions runs the release gate on Apple Silicon and Intel macOS runners with
read-only repository permissions. The official checkout action is pinned to a
specific commit and does not persist credentials. The exact release commit must
pass both jobs before the release is final.

## Remaining boundaries

Physical Intel operation, the complete macOS 13+ range, broad DAW/plugin host
compatibility, full VoiceOver use and a clean-account installation are not
established by these checks. Website, DAW and software-manager recognition remains
intentionally limited; unknown products are still inventoried. Architecture does
not prove DAW or operating-system compatibility. In-app removal handles only the
reviewed bundles shown in its confirmation flow and does not promise a complete
vendor-specific uninstall.

This is an engineering and publication review, not professional legal advice or
a guarantee that every jurisdictional obligation has been identified. The current
project is distributed as non-monetised open-source software; commercial activity,
paid support, accounts or broader personal-data processing would require another
legal and privacy review.
