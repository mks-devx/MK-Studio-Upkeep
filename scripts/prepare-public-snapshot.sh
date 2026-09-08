#!/bin/zsh
# SPDX-License-Identifier: BUSL-1.1
# Build the public source snapshot: the committed tree as one fresh commit, without the
# private development history, ignored folders, untracked files, or anything marked
# export-ignore in .gitattributes. Runs the publication audits on the result and removes
# the output if any check fails. Creates no remote and pushes nothing.
set -euo pipefail
cd "${0:A:h:h}"
DEST="${1:?Usage: PUBLIC_GIT_NAME=… PUBLIC_GIT_EMAIL=… prepare-public-snapshot.sh NEW_EMPTY_DIRECTORY}"
DEST="${DEST:a}"
NAME="${PUBLIC_GIT_NAME:?Set PUBLIC_GIT_NAME to the author name that should appear on the public commit}"
EMAIL="${PUBLIC_GIT_EMAIL:?Set PUBLIC_GIT_EMAIL to the author e-mail that should appear on the public commit}"
fail() { echo "$1" >&2; rm -rf "$DEST"; exit 1; }
[[ -e "$DEST" ]] && { echo "Destination exists: $DEST" >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Commit or stash tracked changes first." >&2; exit 1; }
# git archive reads export-ignore from the committed tree, so the exclusion list must be tracked.
git ls-files --error-unmatch .gitattributes >/dev/null 2>&1 \
    || { echo "Commit .gitattributes first: it lists the private files kept out of the snapshot." >&2; exit 1; }
mkdir -p "$DEST"
trap 'echo "Snapshot failed; removed $DEST" >&2; rm -rf "$DEST"' ERR
git archive --format=tar HEAD | tar -x -C "$DEST"
# Nothing marked export-ignore may exist in the output, whatever git archive decided.
git ls-files -z | git check-attr --stdin -z export-ignore | python3 -c '
import sys
fields = sys.stdin.buffer.read().split(b"\0")
for i in range(0, len(fields) - 2, 3):
    if fields[i + 2] == b"set":
        sys.stdout.buffer.write(fields[i] + b"\n")' | while IFS= read -r excluded; do
    [[ -e "$DEST/$excluded" ]] && fail "Excluded file present in snapshot: $excluded"
done
rm -rf "$DEST/marketing" "$DEST/.local-private" 2>/dev/null || true
cd "$DEST"
# The snapshot's git never sees the private machine's configuration (signing keys, hooks, templates).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init -q
git add -A
git -c user.name="$NAME" -c user.email="$EMAIL" commit -q -m "MK Studio Upkeep 0.2.0 — first public source release"
[[ "$(git log --format='%ae%n%ce' | sort -u)" == "$EMAIL" ]] || fail "An identity other than PUBLIC_GIT_EMAIL reached the snapshot."
python3 scripts/audit-public.py --history
python3 scripts/audit-licensing.py
trap - ERR
echo "Snapshot ready at $DEST with one commit by $(git log -1 --format='%an <%ae>'). Review it, then add the remote and push."
