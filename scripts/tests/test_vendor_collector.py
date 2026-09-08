# SPDX-License-Identifier: BUSL-1.1
import datetime as dt
import importlib.util
import json
import pathlib
import unittest
import subprocess
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('collector', pathlib.Path(__file__).parents[1] / 'collect-vendor-releases.py')
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
# Original minimal fixtures modelling structural fields; no copied vendor page bodies.
D16 = '''<h5 class="card-header">Drumazon 2 <div>2.0.7</div></h5>
<a href="https://cdn.d16.pl/installers/Drumazon2/Drumazon2-2.0.7.dmg"><i></i> Mac OS</a>
<a href="https://cdn.d16.pl/installers/Drumazon2/Drumazon2-2.0.7.msi">Windows 64-Bit</a>'''
KHS = '''<p>all have the same version number</p>
<a href="/data/install/_/mac"><span>Kilohearts Installer</span><i>2.4.6 for Mac</i></a>
<h3><a href="/changelog#2.4.6">2.4.6</a></h3>'''

class CollectorTests(unittest.TestCase):
    def test_cli_requires_an_explicit_catalogue(self):
        with tempfile.TemporaryDirectory() as root:
            output = pathlib.Path(root) / 'review'
            command = [sys.executable, str(pathlib.Path(__file__).parents[1] / 'collect-vendor-releases.py'), '--output-dir', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('--catalogue', result.stderr)
            self.assertFalse(output.exists())

    def test_no_network_sources_are_configured(self):
        self.assertEqual(c.allowed_urls(), set())
        self.assertEqual(c.SOURCES, {})

    def test_network_fetch_is_rejected_before_transport(self):
        with patch('urllib.request.build_opener', side_effect=AssertionError('network reached')):
            for url in ['https://retired-index.example/api/software/example.json', 'https://d16.pl/installers']:
                with self.assertRaises(ValueError): c.fetch(url)

    def test_offline_collection_preserves_dates_versions_and_input(self):
        snapshot = {'sequence': 1, 'generatedOn': '2026-01-01', 'plugins': [], 'daws': []}
        candidate, report = c.collect(snapshot, fetcher=lambda url: self.fail('unexpected fetch'))
        self.assertEqual(candidate, snapshot)
        self.assertIsNot(candidate, snapshot)
        self.assertEqual(report['changes'], [])
        self.assertEqual(report['sources'], [])

    def test_d16_fixture_parser(self):
        self.assertEqual(c.parse_d16(D16)['drumazon2']['version'], '2.0.7')
        with self.assertRaises(ValueError): c.parse_d16(D16.replace('Mac OS', 'Windows'))

    def test_shared_version_fixture_requires_agreement(self):
        self.assertEqual(c.parse_kilohearts(KHS)['version'], '2.4.6')
        with self.assertRaises(ValueError): c.parse_kilohearts(KHS.replace('#2.4.6', '#2.4.7'))

class VoxengoTests(unittest.TestCase):
    PAGE = '<h2><a title="Elephant">Voxengo Elephant</a></h2><b>Version 5.8, October 3, 2025</b><a href="https://www.voxengo.com/files/VoxengoElephant_58_Mac_AU_AAX_VST_setup.dmg">Download AU, AAX, VST3 for Mac</a>'

    def test_mac_identity_and_version_must_agree(self):
        self.assertEqual(c.parse_voxengo(self.PAGE)['elephant']['version'], '5.8')
        for page in [self.PAGE.replace('_58_', '_57_'), self.PAGE.replace('for Mac', 'for Windows'), self.PAGE + self.PAGE, self.PAGE.replace('www.voxengo.com/files', 'evil.example/files')]:
            with self.assertRaises(ValueError): c.parse_voxengo(page)

    def test_unreviewed_source_is_not_fetched(self):
        with self.assertRaises(ValueError):
            c.fetch('https://www.voxengo.com/downloads/')
        called = []
        original = {'sequence': 1, 'plugins': [dict(vendorIdentifierPrefixes=['com.voxengo.audio-plugins.'], productAliases=['Elephant'], latestVersion='5.7', checkedOn='2026-01-01')]}
        def fetch(url):
            called.append(url)
            return fetch_fixtures()(url)
        candidate, _ = c.collect(original, fetch)
        self.assertTrue(all('voxengo' not in url for url in called))
        self.assertEqual(candidate['plugins'], original['plugins'])

    def test_free_heading_does_not_borrow_next_products_download(self):
        free = self.PAGE.replace('Elephant', 'Correlometer').replace('</a></h2>', '</a><span>free</span></h2>')
        releases = c.parse_voxengo(free + self.PAGE)
        self.assertEqual(set(releases), {'elephant', 'correlometer'})
        broken = free.replace('Download AU, AAX, VST3 for Mac', 'Windows')
        self.assertNotIn('correlometer', c.parse_voxengo(broken + self.PAGE))

if __name__ == '__main__': unittest.main()
