# Processor findings

The scanner reads each installed executable's Mach-O architecture declarations without loading it. It distinguishes Apple Silicon, Intel 64-bit and 32-bit code, and preserves unknown results for unreadable or incomplete headers. Different copies can produce different findings.

The Mac's processor is separate from whether MK Studio Upkeep itself is running through Rosetta. Neither executable headers nor Rosetta presence establishes successful plugin loading, DAW support, licensing or audio stability.

Intel-only files may need a compatible host mode or a newer vendor build. Apple Silicon-only files cannot run on Intel. 32-bit-only plugins cannot run on supported macOS versions. Unknown architecture is not proof of incompatibility.

General host guidance links to official documentation and is separate from installed-file facts. It is not certification of an exact plugin, release or format. The app does not install Rosetta, change DAW mode or execute plugin code.

See [platform support](PLATFORM_SUPPORT.md) and [release verification](RELEASE_VERIFICATION.md) for actual runtime coverage.
