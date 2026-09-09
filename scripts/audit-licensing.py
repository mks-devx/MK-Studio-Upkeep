#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Check current release notice consistency; not legal or ownership clearance."""
from pathlib import Path
import hashlib
import plistlib
import subprocess
import sys

# Official GNU AGPL v3 text from the Free Software Foundation.
LICENSE_SHA256 = '0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0'
IDENTIFIER = 'AGPL-3.0-only'
TITLE = 'GNU Affero General Public License v3.0'


def audit(root, paths):
    failures = []
    notices = 0
    licence = root / 'LICENSE'
    if not licence.is_file() or hashlib.sha256(licence.read_bytes()).hexdigest() != LICENSE_SHA256:
        failures.append('LICENSE: expected official AGPL-3.0 text')
    for name in dict.fromkeys(paths):
        path = root / name
        if not name or not path.is_file():
            continue
        if path.suffix in ('.swift', '.py', '.sh') and name.split('/')[0] in ('Sources', 'Tests', 'scripts', 'marketing'):
            for line in path.read_text().splitlines()[:4]:
                if line.startswith(('// SPDX-License-Identifier:', '# SPDX-License-Identifier:')):
                    notices += 1
                    if line.split(':', 1)[1].strip() != IDENTIFIER:
                        failures.append(f'{name}: inconsistent source licence notice')
        if path.suffix in ('.md', '.swift', '.py', '.sh', '.plist', '.yml', '.txt') and path.name != 'audit-licensing.py':
            if 'LicenseRef-' + 'Studio-Upkeep' in path.read_text(errors='replace'):
                failures.append(f'{name}: obsolete custom licence identifier')
    if notices == 0:
        failures.append('No source licence notices found')
    try:
        with (root / 'Resources/Info.plist').open('rb') as stream:
            description = plistlib.load(stream).get('NSHumanReadableCopyright', '')
        if TITLE not in description:
            failures.append('Resources/Info.plist: inconsistent licence description')
    except (OSError, ValueError, plistlib.InvalidFileException):
        failures.append('Resources/Info.plist: missing or invalid metadata')
    required = {
        'README.md': '[GNU Affero General Public License v3.0](LICENSE)',
        'CONTRIBUTING.md': '[AGPL-3.0](LICENSE)',
        'LICENSING.md': 'https://github.com/mks-devx/MK-Studio-Upkeep',
        'Sources/ProducerUpToDateApp/SettingsView.swift': TITLE,
        'scripts/build-app.sh': 'Resources/LICENSING.md',
    }
    for name, phrase in required.items():
        path = root / name
        if not path.is_file() or phrase not in path.read_text():
            failures.append(f'{name}: missing current licence or source reference')
    for name in ('COMMERCIAL_LICENSE.md', 'CONTRIBUTOR_AGREEMENT.md'):
        if (root / name).exists():
            failures.append(f'{name}: retired licensing terms must not ship')
    for name in ('README.md', 'CONTRIBUTING.md', 'Sources/ProducerUpToDateApp/SettingsView.swift',
                 'Resources/Info.plist', 'docs/PRODUCT_DESCRIPTION.md', 'docs/ARCHITECTURE.md',
                 'docs/PUBLIC_RELEASE_PLAN.md', '.github/PULL_REQUEST_TEMPLATE.md', 'scripts/build-app.sh'):
        path = root / name
        if not path.is_file():
            continue
        text = path.read_text().lower()
        for phrase in ('busl-1.1', 'business source license', 'source-available', 'four years after',
                       'commercial_license.md', 'contributor_agreement.md'):
            if phrase in text:
                failures.append(f'{name}: obsolete current licensing wording')
        for phrase in ('current source uses mpl-2.0', 'current source is free and open source under mpl-2.0',
                       'this source is licensed under the mozilla public license'):
            if phrase in text:
                failures.append(f'{name}: obsolete MPL wording for current source')
    return failures, notices


def main():
    root = Path(__file__).resolve().parent.parent
    paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    failures, notices = audit(root, paths)
    for failure in failures:
        print('REVIEW ' + failure)
    print(f'Licence consistency: {len(failures)} finding(s); {notices} notices checked. Not legal clearance.')
    return bool(failures)


if __name__ == '__main__':
    sys.exit(main())
