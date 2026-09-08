#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Collect known official releases into an unsigned, reviewable candidate. Never publish/sign."""
import argparse
import copy
import datetime as dt
import hashlib
import html
import json
import pathlib
import re
import time
import urllib.parse
import urllib.request

MAX_BYTES = 2_000_000
# Pause between live requests so a run never bursts at a vendor or the package index.
POLITENESS_SECONDS = 0.5
USER_AGENT = 'StudioUpkeep-collector (maintainer review tool; +https://github.com/mks-devx/MK-Studio-Upkeep)'
# Parsers are retained for offline fixtures only.
# No vendor page collection until source-use permission is documented.
SOURCES = {}
PAGE_SOURCES = {**SOURCES, 'kilohearts': 'https://kilohearts.com/download'}
PREFIXES = {'d16': 'com.d16group.', 'kilohearts': 'com.kilohearts.', 'voxengo': 'com.voxengo.audio-plugins.',
            'fabfilter': 'com.fabfilter.', 'tdr': 'com.tokyodawnlabs.'}
VERSION = r'[0-9]+(?:\.[0-9]+){1,3}'
# Voxengo: the website terms remain unresolved and the RSS feed at voxengo.com/rss/ is a
# press-release feed (discount announcements) without per-release version data for the
# catalogued products, checked 2026-09-06. Keep the synthetic parser tests; fetch nothing.

def clean(value):
    return ' '.join(html.unescape(re.sub(r'<[^>]*>', ' ', value)).split())

def canonical(value):
    return ''.join(c for c in value.lower() if c.isalnum())

def numeric(value):
    if not re.fullmatch(VERSION, value):
        raise ValueError('Non-stable or malformed version')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (4 - len(parts))

def d16_download(url, name, version):
    # Exact version-bound Mac installer path; no accounts, tokens or mutable "latest" link.
    slug = name.replace(' ', '')
    if not re.fullmatch(r'[A-Za-z0-9]+', slug):
        raise ValueError('Unexpected D16 product name')
    expected = f'https://cdn.d16.pl/installers/{slug}/{slug}-{version}.dmg'
    if url != expected:
        raise ValueError('Unexpected D16 installer destination')
    return url

def parse_d16(page):
    # Linear scan: heading positions first, then slices between them. A page full of unterminated
    # headings therefore costs O(n), not the quadratic time of a lazy `.*?` across the document.
    headings = list(re.finditer(r'<h5\b[^>]*class="card-header"[^>]*>', page, re.I))
    if not headings:
        raise ValueError('D16 page layout changed')
    blocks = []
    for index, start in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(page)
        section = page[start.end():end]
        close = re.search(r'</h5>', section, re.I)
        if close is None:
            raise ValueError('D16 page layout changed')
        blocks.append((section[:close.start()], section[close.end():]))
    releases = {}
    for heading, body in blocks:
        match = re.fullmatch(r'(.+?)\s+(' + VERSION + r')', clean(heading))
        if not match:
            raise ValueError('Unrecognized D16 product heading')
        name, version = match.groups()
        links = [html.unescape(url) for url, label in re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>', body, re.S | re.I) if clean(label) == 'Mac OS']
        if len(links) != 1 or canonical(name) in releases:
            raise ValueError('Missing or ambiguous D16 Mac release')
        releases[canonical(name)] = {'version': version, 'downloadURL': d16_download(links[0], name, version)}
    return releases

def parse_kilohearts(page):
    # Installer label and latest changelog heading must agree; shared-version scope is explicit.
    if 'all have the same version number' not in clean(page):
        raise ValueError('Kilohearts shared-version statement missing')
    labels = re.findall(r'<a\b[^>]*href="/data/install/_/mac"[^>]*>(.*?)</a>', page, re.S | re.I)
    versions = [re.fullmatch(r'Kilohearts Installer\s*(' + VERSION + r') for Mac', clean(label)) for label in labels]
    headings = re.findall(r'<h3>\s*<a href="/changelog#(' + VERSION + r')">', page)
    if len(versions) != 1 or versions[0] is None or not headings or versions[0][1] != headings[0]:
        raise ValueError('Kilohearts installer and changelog disagree')
    return {'version': headings[0]}  # Manager installer is not a product-version-bound download.

def parse_voxengo(page):
    blocks = re.findall(r'<h2>(.*?)</h2>(.*?)(?=<h2>|\Z)', page, re.S)
    releases = {}
    for heading, body in blocks:
        title = re.search(r'title="([^"]+)"[^>]*>Voxengo ([^<]+)</a>', heading)
        if not title or clean(title[1]) != clean(title[2]):
            continue
        name = clean(title[1])
        version = re.search(r'<b>Version (' + VERSION + r'),[^<]+</b>', body)
        links = re.findall(r'<a\b[^>]*href="([^"]+)"[^>]*>Download [^<]*for Mac</a>', body)
        if not links:
            continue  # Legacy Windows-only products cannot provide Mac evidence.
        if not version or len(links) != 1:
            raise ValueError('Missing or ambiguous Voxengo Mac release')
        expected = 'https://www.voxengo.com/files/Voxengo' + re.sub(r'[^A-Za-z0-9]', '', name) + '_' + version[1].replace('.', '') + '_Mac_AU_AAX_VST_setup.dmg'
        if html.unescape(links[0]) != expected or canonical(name) in releases:
            raise ValueError('Voxengo product, version and Mac installer disagree')
        releases[canonical(name)] = {'version': version[1]}
    if not releases:
        raise ValueError('Voxengo page layout changed')
    return releases

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Redirect refused; review the official source configuration')

def allowed_urls():
    return set()

def fetch(url):
    if url not in allowed_urls():
        raise ValueError('Source is not allowlisted')
    time.sleep(POLITENESS_SECONDS)
    expected_type = 'text/html'
    opener = urllib.request.build_opener(NoRedirect)
    request = urllib.request.Request(url, headers={'Accept': expected_type, 'User-Agent': USER_AGENT})
    with opener.open(request, timeout=20) as response:
        if response.status != 200 or response.url != url or response.headers.get_content_type() != expected_type:
            raise ValueError('Unexpected response')
        data = response.read(MAX_BYTES + 1)
        if len(data) > MAX_BYTES:
            raise ValueError('Vendor page exceeds size limit')
        return data.decode('utf-8'), hashlib.sha256(data).hexdigest()

def collect(snapshot, fetcher=fetch, today=None):
    today = today or dt.datetime.now(dt.timezone.utc).date()
    candidate = copy.deepcopy(snapshot)
    report = {'baseSequence': snapshot['sequence'], 'observedOn': today.isoformat(), 'sources': [], 'changes': [],
              'proposedAdditions': [], 'requiresReview': True}

    def apply_plugin_updates(vendor, prefix, resolve, source_url):
        updates = []
        for index, record in enumerate(snapshot['plugins']):
            if record['vendorIdentifierPrefixes'] != [prefix]:
                continue
            found = resolve(record)
            if found is None:
                continue  # Products without a configured source keep their old evidence.
            if numeric(found['version']) < numeric(record['latestVersion']):
                raise ValueError('Vendor version regressed; manual investigation required')
            revised = copy.deepcopy(record)
            revised.update(latestVersion=found['version'], checkedOn=today.isoformat())
            if 'sourceURL' in found:
                revised['sourceURL'] = found['sourceURL']
            if 'downloadURL' in found:
                revised['downloadURL'] = found['downloadURL']
            updates.append((index, revised))
        if not updates:
            raise ValueError('No configured products matched')
        for index, revised in updates:
            candidate['plugins'][index] = revised
            report['changes'].append({'product': revised['productAliases'][0], 'oldVersion': snapshot['plugins'][index]['latestVersion'],
                                      'version': revised['latestVersion'], 'downloadURL': revised.get('downloadURL')})
        return len(updates)

    for vendor, url in SOURCES.items():
        try:
            page, digest = fetcher(url)
            releases = {'d16': parse_d16, 'kilohearts': parse_kilohearts}[vendor](page)
            def resolve(record, releases=releases, vendor=vendor, url=url):
                found = releases.get(canonical(record['productAliases'][0])) if vendor != 'kilohearts' else releases
                if not found:
                    raise ValueError('A catalogued product disappeared from the source')
                return dict(found, sourceURL=url)
            count = apply_plugin_updates(vendor, PREFIXES[vendor], resolve, url)
            report['sources'].append({'vendor': vendor, 'url': url, 'sha256': digest, 'status': 'collected', 'products': count,
                                      'basis': 'Fixed official page; robots.txt permissive 2026-09-06; written terms review pending'})
        except Exception as error:
            # Source batch is transactional. No partial evidence refresh on parse/fetch failure.
            report['sources'].append({'vendor': vendor, 'url': url, 'status': 'failed', 'reason': str(error)})

    if report['changes']:
        candidate['sequence'] = snapshot['sequence'] + 1
        candidate['generatedOn'] = today.isoformat()
    return candidate, report

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalogue', type=pathlib.Path, required=True, help='Explicit input snapshot; no release catalogue is bundled')
    parser.add_argument('--output-dir', type=pathlib.Path, required=True, help='New directory for unsigned candidate and review report')
    args = parser.parse_args()
    # Refuse overwrite, including the editable catalogue or any existing review directory.
    args.output_dir.mkdir(parents=True, exist_ok=False)
    snapshot = json.loads(args.catalogue.read_text())
    candidate, report = collect(snapshot)
    for name, value in [('candidate.json', candidate), ('review.json', report)]:
        with (args.output_dir / name).open('x') as output:
            json.dump(value, output, indent=2, ensure_ascii=False)
            output.write('\n')
    failed = sum(source['status'] == 'failed' for source in report['sources'])
    print(f"Collected {len(report['changes'])} product observations; {failed} source failures; {len(report['proposedAdditions'])} uncatalogued proposals. Unsigned candidate requires review; nothing published.")
    return 1 if failed else 0

if __name__ == '__main__':
    raise SystemExit(main())
