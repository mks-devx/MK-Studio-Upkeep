# Release process

Version 0.3.0 was the first open-source release. Version 0.4.0 changes the current
source licence to AGPL-3.0 and adds protected removal backups. The public repository
began from a reviewed source snapshot; private development history and beta releases
remain excluded. A stable release label does not establish compatibility with every
studio setup.

## Release checks

- Review the manual, settings, interface copy and release notes against the actual app.
- Run publication, licence and packaged-file audits, core regressions and application-state checks.
- Exercise native navigation, settings, scanning and accessible confirmation controls. Use disposable synthetic files for removal tests.
- Build both executable architectures and record the runtime configurations actually tested.
- Audit the distribution snapshot and reachable GitHub history. Keep local evidence, credentials and real inventories outside uploads.
- Sign with the existing publisher identity, notarise and staple the exact app and disk image. Verify the mounted installer and published download against its checksums.
- Run hosted CI where available; record unavailable checks explicitly.

See [release verification](RELEASE_VERIFICATION.md) for the completed evidence and remaining limits. A pending gate must not be reported as passed.

## Publication checks

Verify private vulnerability reporting, support access, source and asset scope,
and public documentation before each release. The current source uses AGPL-3.0;
open-source licensing does not establish legal clearance or replace applicable
publisher and privacy notices.

## Distribution boundary

The app targets macOS 13 and later with a universal executable. A build for Intel is not physical Intel runtime validation. In-app removal remains limited, separately labelled and protected; it is not a promise of complete vendor uninstallation.

Upload only the reviewed source, release description, signed disk image and checksum file. Signing credentials, notarisation records, test inventories and development backups remain local.
