# Contributing

MK Studio Upkeep is a free, source-available macOS scanner and maintenance utility
under the [Business Source License 1.1](LICENSE).
Contributions must preserve local processing, read-only scanning, explicit unknown states and preview-first cleanup.

1. Describe the problem and expected behaviour, using synthetic or redacted evidence.
2. Make a focused change using Swift 6 and the existing Swift Package layout.
3. Add regression fixtures for parser, matching, cancellation, catalogue or cleanup changes. Never test removal against a real studio inventory.
4. Test fixtures must be synthetic: write minimal markup or JSON that models the structural fields a parser inspects. Never commit saved vendor pages, feeds, changelogs, installers or screenshots of vendor sites, even trimmed. Do not run live readers merely to exercise a parser.
5. Run `./scripts/check.sh` and inspect the actual app for interface changes. Include the macOS version, architecture and checks performed in the review.
6. Keep generated builds, keys, personal paths, vendor binaries, presets and licences out of the repository.

Before a contribution is merged, explicitly accept the
[Contributor Agreement 1.0](CONTRIBUTOR_AGREEMENT.md) for that contribution.
You retain copyright and grant rights that permit commercial and proprietary
sublicensing, including integration into the maintainer's other software. A pull request alone is not consent.
Maintainers must record acceptance and review rights before merging. Preserve
copyright and licence notices, disclose copied/adapted material and material AI
assistance, and obtain any required employer permission. Do not include material
whose terms conflict with the required grants.

Developer-destination contributions must use official sources, conservative bundle-identity matching and synthetic fixtures. Record the review date and explain whether the destination is a product page, developer downloads page or software manager. Do not add a list of supposedly current plugin versions. Catalogue and release-engine targets remain experiments; changing them does not enable an app service.

The scanner library must stay independent of SwiftUI, account systems and product
pricing. Commercial incorporation requires the necessary rights or separate
written permission. See [reuse boundaries](docs/ARCHITECTURE.md).

Publication and hosted service changes require maintainer approval. CI validates local work; it does not publish releases.
