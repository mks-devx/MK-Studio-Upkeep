#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check packaged files for embedded developer paths without printing values."""
import pathlib
import re
import sys
root = pathlib.Path(sys.argv[1])
pattern = re.compile(rb"/(?:Users|Volumes)/[^\x00\s]+|\b(?:clau" + rb"de|co" + rb"dex)\b", re.I)
failures = []
for path in root.rglob("*"):
    if path.is_file() and pattern.search(path.read_bytes()):
        failures.append(str(path.relative_to(root)))
for path in failures:
    print("Embedded personal path requires review:", path)
print(f"Packaged-file path audit: {len(failures)} finding(s).")
sys.exit(bool(failures))
