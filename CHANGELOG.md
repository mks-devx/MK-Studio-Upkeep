# Changelog

## 0.2.0 — 8 September 2026

The first stable release focuses on local audio-software inventory and clear official update destinations.

### Inventory and Review

- Read-only AU, VST3, VST2 and CLAP inventory, with installed versions, formats, architectures and individual file copies.
- Separate views for recognised DAWs, software managers, hardware and audio/MIDI drivers.
- Review Intel-only files, architecture mismatches, differing installed versions, repeated formats and suggested related editions.
- Match reviewed developer websites locally. Open installed software managers after signature checks and publisher confirmation.
- Keep limited, dated newer-edition information separate from updates and licence eligibility.
- Inspect scan scope and export selected inventory information locally.

### Interface and reliability

- Simplified result headers, sidebar Review navigation and progressively disclosed file details.
- Consistent Review choices in top navigation, clearer empty results and accurate filtered counts.
- Reorganised settings, live technical-detail preferences and separate app-release controls in About.
- Visible rescan failures preserve the previous inventory without presenting it as fresh.
- Unknown MIDI availability remains unknown.
- Bounded metadata and signature inspection reject unsafe file types; displayed filenames are sanitised.
- Updated manual, privacy policy, installation instructions and project documentation.

### Maintenance and boundaries

- Optional software removal uses a file preview, explicit selection, a timed confirmation and macOS Trash. It remains experimental.
- Driver files and protected content have no generic removal action. Cache inspection remains read-only.
- Automatic plugin/DAW release checks and the former package-index integration are removed. Scanning does not search the internet or upload inventory.
- MK Studio Upkeep's own release action is separate from audio-software information.

See [release verification](docs/RELEASE_VERIFICATION.md) for test, signing and distribution evidence, and [platform support](docs/PLATFORM_SUPPORT.md) for runtime limitations.
