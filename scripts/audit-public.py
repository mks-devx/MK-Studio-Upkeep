#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Conservative local publication audit. Reports categories/locations, never values.

Scans the files that would ship in the public snapshot: tracked and
untracked-but-not-ignored paths, minus anything marked `export-ignore` in
.gitattributes. Looks for secrets, personal paths, personal e-mail domains and
phrases that belong to private working notes rather than public documentation.
Extra private patterns (one regular expression per line, case-insensitive) may be
kept in the ignored file .local-private/audit-patterns.txt; that file is never
published, so the identifiers it protects are not disclosed by this script.
"""
import os
import re
import subprocess
import sys

PATTERNS = {
    "assistant-reference": re.compile(rb"\b(?:clau" + rb"de|co" + rb"dex)\b", re.I),
    "private-key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "credential": re.compile(rb"(?:AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|sk-(?:proj-)?[A-Za-z0-9_-]{32,})"),
    "personal-path": re.compile(rb"/(?:Users|Volumes)/[^\s\"'<>]+"),
    "personal-email": re.compile(
        rb"[A-Za-z0-9._%+-]+@(?:gmail|googlemail|icloud|me|hotmail|outlook|live|yahoo|proton|protonmail|gmx)\.[a-z.]+", re.I),
    "working-note": re.compile(
        rb"(?:Applications copy|Unlock the Mac|development machine|review machine|this machine'?s inventory|"
        rb"(?:A|the) user(?:'s)? screenshot|locally observed|(?:local|private|Git) checkpoints?|"
        rb"was not (?:replaced|installed over)|The Mac was locked)", re.I),
    "owner-inventory": re.compile(
        rb"(?:Real(?:-machine|(?: local)?(?: app| machine| studio))? (?:scan|smoke test)\b|real local scanner|"
        rb"scanned \d{3,} files|\d{3,} (?:plugin )?(?:files|bundles) ?(?:/|and|into|,) ?\d{3,} (?:normalized |visible )?products|"
        rb"on (?:the|this) (?:development|review|local) (?:machine|Mac))", re.I),
}
PRIVATE_PATTERN_FILE = ".local-private/audit-patterns.txt"


def git(*args, stdin=None):
    return subprocess.run(["git", *args], input=stdin, capture_output=True, check=True).stdout


def shipped_paths():
    """Paths git archive would export: tracked + untracked-not-ignored, minus export-ignore."""
    paths = [p for p in git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0") if p]
    if not paths:
        return []
    out = git("check-attr", "--stdin", "-z", "export-ignore", stdin=b"\0".join(paths) + b"\0")
    fields = out.split(b"\0")
    ignored = {fields[i] for i in range(0, len(fields) - 2, 3) if fields[i + 2] == b"set"}
    return [p.decode() for p in paths if p not in ignored]


patterns = dict(PATTERNS)
if os.path.isfile(PRIVATE_PATTERN_FILE):
    with open(PRIVATE_PATTERN_FILE, "rb") as stream:
        private = [line.strip() for line in stream if line.strip() and not line.startswith(b"#")]
    if private:
        patterns["private-pattern"] = re.compile(b"(?:" + b"|".join(private) + b")", re.I)

# Phrase categories are matched against printable strings inside binary files; secrets and
# paths are checked against every byte.
TEXT_ONLY = {"personal-email", "working-note", "owner-inventory", "private-pattern"}
SELF = os.path.relpath(os.path.abspath(__file__))

failures = set()
for path in shipped_paths():
    if path in (PRIVATE_PATTERN_FILE, SELF):
        continue  # This script names the phrases it searches for.
    try:
        with open(path, "rb") as stream:
            data = stream.read()
    except (FileNotFoundError, IsADirectoryError):
        continue
    # Binary files (icons, images, PDFs) carry text only in metadata chunks: scan their printable
    # runs for the phrase categories instead of the raw bytes, which would only yield accidental hits.
    binary = b"\0" in data[:8192]
    strings = b"\n".join(re.findall(rb"[\x20-\x7e]{6,}", data)) if binary else data
    for kind, pattern in patterns.items():
        if pattern.search(strings if kind in TEXT_ONLY else data):
            failures.add((path, kind))
    if path.endswith((".key", ".p12", ".p8", ".pem")) or ".local-private/" in path:
        failures.add((path, "private-material-filename"))
if "--history" in sys.argv:
    objects = git("rev-list", "--objects", "--all").splitlines()
    for line in objects:
        parts = line.split(b" ", 1)
        if len(parts) != 2:
            continue
        oid, path = parts
        if path.endswith(b"scripts/audit-public.py") or path.endswith(PRIVATE_PATTERN_FILE.encode()):
            continue  # The script's own pattern strings are not findings.
        if git("cat-file", "-t", oid.decode()).strip() != b"blob":
            continue
        data = git("cat-file", "blob", oid.decode())
        for kind, pattern in patterns.items():
            if pattern.search(data):
                failures.add(("history:" + path.decode(), kind))
    authors = set(git("log", "--all", "--format=%ae%n%ce").splitlines())
    print(f"History inspected; {len(authors)} unique Git author/committer email identities require owner review before publication.")
    for author in sorted(authors):
        if patterns["personal-email"].search(author):
            failures.add(("history:author-identity", "personal-email"))
for path, kind in sorted(failures):
    print(f"REVIEW {kind}: {path}")
print(f"Publication pattern audit: {len(failures)} finding(s). This is not a guarantee that no secret or provenance issue exists.")
sys.exit(bool(failures))
