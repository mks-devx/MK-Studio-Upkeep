# Developer websites and software managers

The stable-version flow matches destinations during the local scan. It does not
perform live website discovery, scrape search results, fetch current releases or
compare them with installed plugin/DAW versions. Website research happens while
maintaining the directory, not by uploading a user's inventory.

`ProductDestinations` contains version-free reviewed developer links and reuses the
existing `ManagerDefinition` and DAW website directories. Matching requires known
bundle identifiers; names alone do not create official links. Unknown destinations
say **Official website not identified**. A link can be a developer-wide downloads,
products or manager page; it does not claim to be an exact product update endpoint.

The product view shows version, architectures, relevant findings and website/manager
actions first. Installed files, technical details and uninstall options are collapsed.
Manager buttons use the existing verified-signature opening flow. Finding an app by
name is not proof that it owns an installation or belongs to a specific publisher.

## Local findings

- **Cannot run on this Mac:** 32-bit-only files, or Apple Silicon-only files on Intel.
  This follows [Apple's 32-bit support boundary](https://support.apple.com/103076).
- **Intel-only:** separate from incompatibility; host mode and Rosetta matter.
- **Different installed versions:** compares local copy metadata, not remote releases.
- **Multiple copies of one format:** distinct files of the same format; AU and VST3
  are not duplicates. No removal is suggested automatically.
- **Related editions installed:** names and matching installed major versions suggest
  a common family within one developer identity. These are labelled suggestions;
  the inventory never merges or deletes them. Existing projects may need both.

The app does not recommend newer editions. Official developer websites provide
somewhere to check release information and licence options yourself.

File age alone never means obsolete or broken. Discontinued/vendor-unsupported status
needs product-specific official evidence; no speculative discontinued list is shipped.
Unknown architecture and host compatibility stay unknown.

## Website review — 8 September 2026

The Antelope downloads page, FabFilter download page, Cableguys products page,
Tokyo Dawn Labs products page, u-he products page and D16 downloads page were reached
successfully. Cableguys' old downloads address redirected to products; the directory
uses the destination. Valhalla's official downloads page is documented by its own
support pages, but the command-line request returned HTTP 403; browser availability
was not established by that request. No access restriction was bypassed.

Manager destinations retain their references in [Manager sources](MANAGER_SOURCES.md).
DAW destinations retain the existing reviewed mapping. They are pointers, not ongoing
availability monitoring. This is limited directory coverage, not universal discovery.

The earlier official-release integration and declared-feed diagnostics remain in
separate targets for future evaluation. The app no longer depends on them, includes
no automatic-check controls and does not package their source-directory resource.
MK Studio Upkeep's own GitHub update check stays separate.
