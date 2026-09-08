# Architecture

MK Studio Upkeep is a native macOS SwiftUI application. Historical `ProducerUpToDateCore` and executable module names are retained to preserve source compatibility. The bundle identity remains unchanged across upgrades.

## Active application

- **Scanning:** `ScanPipeline` coordinates cancellable local plugin and DAW scans. Bounded file reads, metadata sanitisation and Mach-O header inspection preserve raw evidence without loading plugin code.
- **Identity and findings:** normalisation groups installed formats while preserving distinct editions and file copies. Architecture, differing versions and possible duplicate/related installs are local findings, not vendor support declarations.
- **Official destinations:** reviewed, version-free identity rules resolve developer websites and installed software managers locally. Unknown identities remain unknown. Small dated edition records describe separately identified upgrades; they do not establish the latest patch release.
- **Hardware:** Core Audio and Core MIDI enumeration reads properties without opening audio streams. Driver inventory is separate from hardware availability.
- **Presentation:** AppKit actions and SwiftUI views belong to the executable target. The split view owns navigation, title and shared search. Settings and optional last-scan records are local.
- **Removal:** core planning and revalidation do not execute deletion. The app supplies macOS Trash only after an explicit file preview and confirmation. Driver files and protected content have no removal action.
- **App releases:** MK Studio Upkeep's manual release action is separate from audio software. Private builds open GitHub Releases; configured public builds use a restricted GitHub metadata reader.

## Experiments retained in source

Generic catalogue validation, release comparison and the isolated update-engine prototype remain separately testable development code. They are not active plugin/DAW update services in the app. The old release catalogue, signed duplicate and pinned catalogue key have been removed from the current source. Tests create minimal synthetic records and signing keys; compatibility catalogue defaults are empty. The maintainer collector has no live network sources and requires an explicit input file.

The standalone catalogue packaging command requires an explicit signed input and trusted public key: `CatalogueTool SIGNED_CATALOGUE PUBLIC_KEY.txt NEW_OUTPUT_DIRECTORY`. It does not provide release data or establish whether a supplied key belongs to a trustworthy publisher. The app's version-free developer-link directory and narrowly reviewed edition relationships remain separate.

`MacArchitecture` distinguishes the Mac's processor from a process running through Rosetta. `InstalledArchitecture` reports executable declarations. Neither proves that a plugin loads successfully or is supported by a particular DAW.

## Reuse and licensing

The scanner can be used independently from presentation and network experiments. There are no third-party Swift package dependencies. Apple frameworks retain their own terms.

Module separation does not grant permission to relicense code. See the [source-available licence](../LICENSE), [contributing guide](../CONTRIBUTING.md) and [contributor agreement](../CONTRIBUTOR_AGREEMENT.md) before incorporating or contributing code.
