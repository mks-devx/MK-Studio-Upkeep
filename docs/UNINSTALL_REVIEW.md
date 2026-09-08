# Uninstall review boundaries

The read-only associated-file search covers common system/current-user Applications
and Library locations plus configured plugin folders. Hidden entries are included;
links and package descendants are skipped. Depth is bounded and the search stops
at 200,000 entries with an incomplete-results warning. Other user accounts and
arbitrary volumes are not exhaustively searched.

Extra software copies need an exact bundle identifier and the same safety checks
as the original bundle. A matching name never proves ownership of support data.
Projects, recovery sessions, presets, samples, libraries, activation information
and unrecognised support folders remain protected.

Each eligible bundle receives a frozen contents preview, bounded to 250,000
entries; the UI displays the first 200 names. Inaccessible or over-limit bundle
contents prevent removal. Paths, types, inode, size, modification times and link
destinations form a manifest rechecked before movement. This detects metadata
changes; it does not eliminate filesystem races. Custom content inside a selected
bundle moves with that bundle and must be backed up first.

## Settings and related data stay in place

Preferences, caches, saved application state and application-support data are
rejected by the removal executor even if a caller explicitly supplies them.
Deep discovery displays identified locations with individual Finder actions and
a Copy kept locations action. The copied text includes search warnings and makes
clear that no backup was created. Empty results never claim no related data exists.
The completion message distinguishes moved software from retained related files.

## Confirmation and recovery

Nothing is preselected. Users acknowledge closed hosts and reviewed files, then
hold for five seconds and release. Early release or Escape cancels the hold.
Changes to selection or consent reset it. Trash remains recoverable until emptied.
The whole plan is validated before movement; later failures stop remaining moves
and report partial results. Eligible system-root moves can use Finder and its
administrator prompt. Home-folder moves never use that escalation route.

Driver removal retains its own protections: kernel/system extensions, Apple
components and protected device dependencies use instructions, not a generic
removal control. A manager suggestion does not prove installation ownership or
uninstall support. Its actual publisher must be reviewed before launch.

## Verification boundaries

Regression fixtures verify that preferences, caches, support data and saved state cannot reach the move operation. Synthetic Trash/restore and native confirmation tests cover disposable files and harmless callbacks. See [release verification](RELEASE_VERIFICATION.md) for the exact candidate results. These checks do not establish safe removal for every vendor layout. Complete VoiceOver and clean-account testing remain separate validation work.
