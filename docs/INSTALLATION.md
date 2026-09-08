# Installation

Download from [MK Studio Upkeep Releases](https://github.com/mks-devx/MK-Studio-Upkeep/releases).
The installer is publicly available without a GitHub account. The app contains
no GitHub credentials and does not download or install its own updates.

1. Download the release's macOS `.dmg` and `SHA256SUMS.txt`.
2. Quit any running copy of MK Studio Upkeep. Keep the previous installer for rollback.
3. Open the disk image and drag **MK Studio Upkeep** to **Applications**.
4. Eject the image, open the app and choose **Scan This Mac**.
5. Use **Settings → Scanning** for extra plugin folders or different scan formats.

The app targets macOS 13 or later and includes Apple Silicon and Intel code.
See [Platform support](PLATFORM_SUPPORT.md) for the tested configurations.
The release notes record signing and notarisation of the actual download.

## Verify the download

In Terminal, run `shasum -a 256` on the downloaded image and compare the result
with its entry in `SHA256SUMS.txt`. Obtain both files from the official release.
A matching checksum confirms matching bytes; it does not replace signature checks.
GitHub's automatically generated source archives are not app installers.

If macOS rejects the download, stop and report the exact message after removing
personal information. Do not disable Gatekeeper or remove quarantine to bypass it.

## Upgrade or remove MK Studio Upkeep

Quit the previous app before replacing it. The bundle identity is retained, so
existing preferences and local scan history continue across upgrades.

To remove MK Studio Upkeep, quit it and move this app to Trash. Your plugins,
DAWs, drivers and managers are separate. Preferences and local scan history remain;
see [Privacy](../PRIVACY.md) for local storage details.
