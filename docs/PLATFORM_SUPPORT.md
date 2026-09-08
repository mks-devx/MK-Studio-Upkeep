# Platform support

MK Studio Upkeep targets **macOS 13 or later**. Distribution builds contain
**Apple Silicon (arm64)** and **Intel (x86_64)** executables. The minimum OS and
universal binary describe the build, not an exhaustive runtime certification.

Runtime verification currently covers native Apple Silicon on macOS 26.5.2.
Physical Intel hardware, Rosetta execution and other macOS releases remain
unverified unless the specific release's verification record says otherwise.
Hosted build/test results are separate from physical studio and audio-host testing.

The scanner does not load plugins or certify that they will work in a DAW.
A plugin may require a newer OS, a particular host mode or additional dependencies.
Unknown requirements remain unknown.

Software and saved MIDI-entry removal are experimental. Untested configurations
show a caution; review and confirmation are still required. Driver-file removal
is disabled on every platform, and cache inspection is read-only.

Builds require Xcode 26 or newer and Swift 6. App users do not need Xcode.
[Release verification](RELEASE_VERIFICATION.md) records the actual checks and limits.

Automated core/app-state checks and universal packaging also passed on the macOS 15 Apple Silicon and Intel GitHub runners. This does not replace physical Intel UI or audio-host testing. See [verification](RELEASE_VERIFICATION.md).
