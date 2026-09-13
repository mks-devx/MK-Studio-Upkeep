# Architecture

MK Studio Upkeep is a native macOS SwiftUI application. Historical `ProducerUpToDateCore` and executable module names are retained to preserve source compatibility. The bundle identity remains unchanged across upgrades.

## Active application

- **Scanning:** `ScanPipeline` coordinates cancellable local plugin and DAW scans. Bounded file reads, metadata sanitisation and Mach-O header inspection preserve raw evidence without loading plugin code.
- **Identity and findings:** normalisation groups installed formats while preserving distinct editions and file copies. Architecture, differing versions and possible duplicate/related installs are local findings, not vendor support declarations.
- **Official destinations:** reviewed, version-free identity rules resolve developer websites and installed software managers locally. Unknown identities remain unknown. Newer-edition recommendations are not part of the current source.
- **Hardware:** Core Audio and Core MIDI enumeration reads properties without opening audio streams. Driver inventory is separate from hardware availability.
- **Presentation:** AppKit actions and SwiftUI views belong to the executable target. The split view owns navigation, title and shared search. Settings and optional last-scan records are local.
- **Removal and recovery:** core planning and revalidation do not execute deletion. Before the app moves eligible bundles to macOS Trash, a separate store copies and verifies every selected item by default. Restore refuses occupied or newly unsafe destinations. Driver files and protected content have no generic removal action.
- **App releases:** MK Studio Upkeep's manual release action is separate from audio software. Private builds open GitHub Releases; configured public builds use a restricted GitHub metadata reader.

## Evidence boundaries

Generic catalogue validation and release comparison types remain in the core with synthetic test records and empty catalogue defaults. They are not active plugin or DAW update services. The obsolete release-feed prototypes, collectors and catalogue packaging tools have been removed from the current source.

The app's version-free developer-link directory remains part of local matching. Related-edition findings compare installed software only.

`MacArchitecture` distinguishes the Mac's processor from a process running through Rosetta. `InstalledArchitecture` reports executable declarations. Neither proves that a plugin loads successfully or is supported by a particular DAW.

## Reuse and licensing

The scanner can be used independently from presentation. There are no third-party Swift package dependencies. Apple frameworks retain their own terms.

The current source is covered by AGPL-3.0. Distribution and network use must
follow its source-availability and notice requirements.
See the [licence](../LICENSE), [licensing guide](../LICENSING.md) and
[contributing guide](../CONTRIBUTING.md).
