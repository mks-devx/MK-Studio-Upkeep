# Build and distribution

Build with Xcode 26 or newer and Swift 6:

```sh
./scripts/check.sh
./scripts/build-app.sh release
```

The build targets macOS 13 and packages arm64 and x86_64 executables. Local output
is ad-hoc signed and checked for accidental build paths. Existing local output is
preserved by the packaging script before replacement. A labelled build can be
selected with `STUDIO_UPKEEP_BUILD_LABEL`.

The optional `STUDIO_UPKEEP_SMOKE=1` launch check opens the normal app with existing
preferences. Scan-on-launch may run, and startup may update the app's own local
data. Use a disposable macOS account when the check needs isolated state. The
default checks do not enable this launch step.

The app bundle contains the executable, branding and licence/privacy files.
No historical release catalogue or catalogue signing key is included in the
current source or packaged app. The isolated update-engine source directory
is not packaged into the scanner app.

## Source publication

Use a reviewed source snapshot with a public-safe Git author identity. Exclude
private development history, ignored data, internal working notes and obsolete
screenshots. Audit both the snapshot and the reachable GitHub history. A source
snapshot must still build and pass tests independently.

Do not store signing keys, credentials, real studio inventories or raw notarisation
records in the source repository. Retain the licence and required attribution.

## Distributable installer

`scripts/package-release.sh` signs a verified app with Developer ID, submits it
for notarisation, staples the accepted ticket, creates and signs a disk image,
then notarises and staples the image. It verifies signatures, image integrity
and Gatekeeper assessment, and writes SHA-256 checksums.

Supply the signing identity and saved notarisation profile externally. Upload
only the final versioned `.dmg` and `SHA256SUMS.txt`; submission records stay local.
Re-download the uploaded files and verify their hashes and contents.

Passing local tests, signing or notarisation alone does not establish stability
across platforms. Record runtime, accessibility and installation coverage in the
[release verification](RELEASE_VERIFICATION.md), with remaining gaps explicitly stated.
