# MK Studio Upkeep releases

The app's own release action is in **Settings → About** and its optional menu-bar icon's menu.
It is separate from plugin/DAW information and never uploads inventory.

In version 0.3.0, **Check GitHub Releases** opens the public release page in your
browser without automatically comparing versions. No GitHub account is needed
to download the installer, and no GitHub credentials are stored in MK Studio Upkeep.

A public build may configure `StudioUpkeepReleaseRepository` for a manual GitHub
API check. It accepts only releases with a nonempty, version-matched macOS disk
image and `SHA256SUMS.txt` hosted on that same release. Drafts are excluded; beta
inclusion is optional and off by default. Nothing downloads or installs itself.

`StudioUpkeepReleaseVersion` preserves beta/RC ordering independently of the
marketing version. Replacing an installer under an unchanged release version
cannot be detected as a new release, so published versions must remain distinct.

Asset presence does not establish checksum contents or installer authenticity.
Distribution signing, notarisation and post-upload verification remain separate.
