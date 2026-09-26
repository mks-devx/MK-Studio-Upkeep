# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile
import unittest

AUDIT = Path(__file__).resolve().parents[1] / 'audit-public.py'


class PublicationAuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        # Exceed pipe capacity in both query input and attribute output.
        for index in range(300):
            (self.root / f'fixture-{index:04d}-{"x" * 80}.txt').write_text('Synthetic fixture\n')

    def audit(self):
        process = subprocess.Popen([sys.executable, str(AUDIT)], cwd=self.root,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            output, errors = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            self.fail('Publication audit stalled on a large file list')
        return process.returncode, output, errors

    def test_large_file_list_completes(self):
        status, output, errors = self.audit()
        self.assertEqual(status, 0, errors)
        self.assertIn('0 finding(s)', output)

    def test_large_file_list_still_checks_findings_and_export_exclusions(self):
        marker = '-----BEGIN ' + 'PRIVATE KEY-----'
        (self.root / 'visible.txt').write_text(marker)
        (self.root / 'excluded.txt').write_text(marker)
        (self.root / '.gitattributes').write_text('excluded.txt export-ignore\n')
        status, output, errors = self.audit()
        self.assertEqual(status, 1, errors)
        self.assertIn('REVIEW private-key: visible.txt', output)
        self.assertNotIn('excluded.txt', output)
        self.assertIn('1 finding(s)', output)
