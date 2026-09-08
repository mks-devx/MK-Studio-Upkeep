# SPDX-License-Identifier: MPL-2.0
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('licensing_audit', ROOT / 'scripts/audit-licensing.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class LicensingAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.paths = ['LICENSE', 'README.md', 'CONTRIBUTING.md', 'LICENSING.md',
                      'Resources/Info.plist', 'Sources/ProducerUpToDateApp/SettingsView.swift',
                      'scripts/build-app.sh']
        for name in self.paths:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def failures(self):
        return audit.audit(self.root, self.paths)[0]

    def test_current_mpl_distribution_passes(self):
        self.assertEqual(self.failures(), [])

    def test_modified_licence_is_rejected(self):
        with (self.root / 'LICENSE').open('a') as stream:
            stream.write('\nAdditional restriction.\n')
        self.assertTrue(any('official MPL-2.0 text' in issue for issue in self.failures()))

    def test_legacy_source_notice_is_rejected(self):
        name = 'Sources/Example.swift'
        (self.root / name).write_text('// SPDX-License-Identifier: ' + 'BUSL' + '-1.1\n')
        self.paths.append(name)
        self.assertTrue(any('inconsistent source' in issue for issue in self.failures()))

    def test_missing_source_guide_is_rejected(self):
        (self.root / 'LICENSING.md').unlink()
        self.assertTrue(any('LICENSING.md' in issue for issue in self.failures()))

    def test_retired_terms_are_rejected(self):
        (self.root / 'COMMERCIAL_LICENSE.md').write_text('Retired terms')
        self.assertTrue(any('retired licensing terms' in issue for issue in self.failures()))
