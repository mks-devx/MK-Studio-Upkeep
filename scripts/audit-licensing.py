#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Check current release notice consistency; not a legal/provenance audit."""
from pathlib import Path
import plistlib
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
identifier = "BUSL-1.1"
title = "Business Source License 1.1"
failures = []
license_text = (root / "LICENSE").read_text()
for required in (title + "\n", "Licensor:", "Licensed Work:", "Additional Use Grant:", "Change Date:",
                 "Change License:", "Mozilla Public License, version 2.0 (MPL-2.0)", "Covenants of Licensor"):
    if required not in license_text:
        failures.append(f"LICENSE: missing BUSL-1.1 element {required.strip()!r}")
if not license_text.startswith(title + "\n"):
    failures.append("LICENSE: expected Business Source License 1.1 title")
if "None" == license_text.split("Additional Use Grant:", 1)[-1].split("\n", 1)[0].strip():
    failures.append("LICENSE: Additional Use Grant must permit free production use, not 'None'")

paths = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root
).decode().split("\0")
notices = 0
for name in dict.fromkeys(paths):
    path = root / name
    if not name or not path.is_file():
        continue
    if path.suffix not in (".swift", ".py", ".sh") or name.split("/")[0] not in ("Sources", "Tests", "scripts", "marketing"):
        continue
    for line in path.read_text().splitlines()[:4]:
        if line.startswith(("// SPDX-License-Identifier:", "# SPDX-License-Identifier:")):
            notices += 1
            if line.split(":", 1)[1].strip() != identifier:
                failures.append(f"{name}: inconsistent source licence notice")
if notices == 0:
    failures.append("No source licence notices found")

with (root / "Resources/Info.plist").open("rb") as stream:
    copyright_text = plistlib.load(stream).get("NSHumanReadableCopyright", "")
if title not in copyright_text:
    failures.append("Resources/Info.plist: inconsistent licence description")
for name, required in {
    "README.md": "[Business Source License 1.1](LICENSE)",
    "CONTRIBUTING.md": "CONTRIBUTOR_AGREEMENT.md",
    "COMMERCIAL_LICENSE.md": "[LICENSE](LICENSE)",
}.items():
    if required not in (root / name).read_text():
        failures.append(f"{name}: missing current licence reference")
if not (root / "CONTRIBUTOR_AGREEMENT.md").is_file():
    failures.append("Missing contributor agreement")
# Wording policy: "free, source-available", never an open-source product claim.
for name in ("README.md", "CONTRIBUTING.md", "Sources/ProducerUpToDateApp/SettingsView.swift", "docs/GITHUB_BETA_DRAFT.md"):
    if not (root / name).is_file():
        continue  # Private working notes are not part of the public snapshot.
    text = (root / name).read_text().lower()
    for phrase in ("free, open-source", "free open-source", "free and open source", "open-source macos", "open-source studio"):
        if phrase in text:
            failures.append(f"{name}: obsolete open-source product claim")
# The obsolete custom licence must not survive anywhere in the public candidate.
for name in dict.fromkeys(paths):
    path = root / name
    if not name or not path.is_file() or path.suffix not in (".md", ".swift", ".py", ".sh", ".plist", ".yml", ".txt"):
        continue
    if path.resolve() == Path(__file__).resolve():
        continue  # This file names the identifier in order to search for it.
    if "LicenseRef-" + "Studio-Upkeep" in path.read_text(errors="replace"):
        failures.append(f"{name}: obsolete custom licence identifier")

for failure in failures:
    print("REVIEW " + failure)
print(f"Licence consistency: {len(failures)} finding(s); {notices} notices checked. Not legal clearance.")
sys.exit(bool(failures))
