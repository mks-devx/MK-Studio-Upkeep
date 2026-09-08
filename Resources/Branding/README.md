# MK Studio Upkeep — Scan mark

`StudioUpkeepScan-master.png` is the Scan mark: six angular signal rails with a
diagonal scan seam. It preserves the source artwork exactly.

`scripts/generate-app-icon.swift` packages that artwork on a dark rounded macOS
tile and produces exact 16–1024 pixel PNG renditions. It preserves the selected
shape and soft edge treatment; it does not regenerate or redraw the mark.

Regenerate locally from the repository root:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift scripts/generate-app-icon.swift
./scripts/build-app.sh release
```

Icon changes do not alter the bundle identity or licence decision.

## Origin

The logo was generated with AI for this project and selected by the maintainer.
The original generation notes are retained in the private development records.
AI generation and selection do not establish exclusivity, copyright protection
or trademark clearance. No originality or clearance guarantee is made.
