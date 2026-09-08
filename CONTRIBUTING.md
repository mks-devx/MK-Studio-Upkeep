# Contributing

MK Studio Upkeep is a free, open-source macOS scanner and maintenance utility
under the [Mozilla Public License 2.0](LICENSE).
Contributions must preserve local processing, read-only scanning, explicit unknown states and preview-first cleanup.

1. Describe the problem and expected behaviour, using synthetic or redacted evidence.
2. Make a focused change using Swift 6 and the existing Swift Package layout.
3. Add regression fixtures for parser, matching, cancellation, catalogue or cleanup changes. Never test removal against a real studio inventory.
4. Test fixtures must be synthetic: write minimal markup or JSON that models the structural fields a parser inspects. Never commit saved vendor pages, feeds, changelogs, installers or screenshots of vendor sites, even trimmed. Do not run live readers merely to exercise a parser.
5. Run `./scripts/check.sh` and inspect the actual app for interface changes. Include the macOS version, architecture and checks performed in the review.
6. Keep generated builds, keys, personal paths, vendor binaries, presets and licences out of the repository.

Contributions to MPL-covered files are submitted under [MPL-2.0](LICENSE).
You retain your copyright. No separate contributor agreement, copyright assignment
or special proprietary-relicensing grant is required for new contributions.
Confirm in your pull request that you have the right to contribute the material
under MPL-2.0. Preserve existing notices, disclose third-party material and its
terms, disclose material AI assistance, and obtain any necessary employer or
other rights-holder permission. Do not submit confidential or incompatible material.
Existing agreements, if any, are not revoked by this policy for new contributions.

Developer-destination contributions must use official sources, conservative bundle-identity matching and synthetic fixtures. Record the review date and explain whether the destination is a product page, developer downloads page or software manager. Do not add a list of supposedly current plugin versions. Catalogue and release-engine targets remain experiments; changing them does not enable an app service.

The scanner library must stay independent of SwiftUI, account systems and product
pricing. Commercial incorporation is permitted subject to MPL-2.0 and any applicable
third-party terms. See [reuse boundaries](docs/ARCHITECTURE.md).

Publication and hosted service changes require maintainer approval. CI validates local work; it does not publish releases.
