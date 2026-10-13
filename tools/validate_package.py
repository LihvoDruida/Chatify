#!/usr/bin/env python3
"""R1-08 gate: validate the real installable ZIP after external libraries are fetched.

This cannot certify live WoW behavior or verify AceDB logout/login. It refuses
SOURCE/overlay packages without externals, traversal, unresolved manifest
includes, and stale TOC versions. Record hashes to bind QA to exact library bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import posixpath
import re
import sys
import zipfile
from pathlib import PurePosixPath
from xml.etree import ElementTree as ET

CORE_LIBS = (
    'LibStub/LibStub.lua',
    'CallbackHandler-1.0/CallbackHandler-1.0.lua',
    'AceAddon-3.0/AceAddon-3.0.xml',
    'AceEvent-3.0/AceEvent-3.0.xml',
    'AceHook-3.0/AceHook-3.0.xml',
    'AceDB-3.0/AceDB-3.0.xml',
    'AceConsole-3.0/AceConsole-3.0.xml',
    'AceGUI-3.0/AceGUI-3.0.xml',
    'LibSharedMedia-3.0/LibSharedMedia-3.0.lua',
    'LibChatAnims/LibChatAnims.xml',
)


def validate(path: str, expected_version: str | None = None) -> dict:
    errors: list[str] = []
    report = {'package': path, 'expected_version': expected_version,
              'status': 'FAIL', 'toc_files': [], 'libraries_sha256': {},
              'checked_includes': 0, 'errors': errors}
    try:
        z = zipfile.ZipFile(path)
    except (OSError, zipfile.BadZipFile) as exc:
        errors.append(f'Cannot open ZIP: {exc}')
        return report
    with z:
        names = z.namelist()
        if len(names) != len(set(names)):
            errors.append('ZIP contains duplicate file paths')
        for n in names:
            p = PurePosixPath(n)
            if n.startswith('/') or '\\' in n or '..' in p.parts or not n.startswith('Chatify/'):
                errors.append('Unexpected/unsafe archive path: ' + n)
        files = set(n for n in names if not n.endswith('/'))
        tocs = sorted(n for n in files if re.fullmatch(r'Chatify/[^/]+\.toc', n))
        if len(tocs) != 8:
            errors.append(f'Expected 8 Chatify TOCs, found {len(tocs)}')
        report['toc_files'] = tocs
        if not expected_version:
            errors.append('Missing expected version: pass --expected-version from Git tag')
        if expected_version and not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z.-]+)?', expected_version):
            errors.append('Invalid expected version: ' + expected_version)
        visited: set[str] = set()

        def inspect_xml(filepath: str):
            if filepath in visited:
                return
            visited.add(filepath)
            if filepath not in files:
                errors.append('Missing include: ' + filepath)
                return
            try:
                root = ET.fromstring(z.read(filepath))
            except (ET.ParseError, OSError) as exc:
                errors.append(f'Malformed XML {filepath}: {exc}')
                return
            for element in root.iter():
                tag = element.tag.rsplit('}', 1)[-1]
                if tag not in ('Script', 'Include'):
                    continue
                value = element.attrib.get('file')
                if not value:
                    errors.append(f'Empty {tag} in {filepath}')
                    continue
                file_ref = posixpath.normpath(posixpath.join(posixpath.dirname(filepath), value.replace('\\', '/')))
                if not file_ref.startswith('Chatify/') or file_ref not in files:
                    errors.append(f'Unresolved {filepath} -> {file_ref}')
                elif tag == 'Include':
                    inspect_xml(file_ref)
                report['checked_includes'] += 1

        for toc in tocs:
            data = z.read(toc).decode('utf-8-sig', 'replace')
            versions = re.findall(r'^## Version:\s*(.*?)\s*$', data, re.M)
            if len(versions) != 1 or (expected_version and versions[0] != expected_version):
                errors.append(f'{toc} Version={versions!r}, expected {expected_version}')
            includes = []
            for raw in data.splitlines():
                line = raw.strip().replace('\\', '/')
                if not line or line.startswith('#'):
                    continue
                if not line.endswith(('.lua', '.xml')):
                    continue
                resolved = posixpath.normpath('Chatify/' + line)
                includes.append(resolved)
                if resolved not in files:
                    errors.append(f'Unresolved {toc} -> {resolved}')
                elif resolved.endswith('.xml'):
                    inspect_xml(resolved)
                report['checked_includes'] += 1
            if 'Chatify/libs/_manifest.xml' not in includes:
                errors.append(toc + ' does not load libs/_manifest.xml')
        for relative in CORE_LIBS:
            full = 'Chatify/libs/' + relative
            if full not in files or z.getinfo(full).file_size <= 0:
                errors.append('Missing/empty required embedded library: ' + full)
                continue
            libname = relative.split('/')[0]
            # Fingerprint the whole embedded library, not just its XML loader:
            # Lua implementation can change while an XML manifest stays identical.
            prefix = 'Chatify/libs/' + libname + '/'
            digest = hashlib.sha256()
            for member in sorted(p for p in files if p.startswith(prefix)):
                digest.update(member.encode('utf-8'))
                digest.update(b'\0')
                digest.update(z.read(member))
            report['libraries_sha256'][libname] = digest.hexdigest()
        for name in files:
            if name.startswith('Chatify/tools/') or name.startswith('Chatify/.git/'):
                errors.append('Source-only content leaked into installation: ' + name)
        # zipfile.testzip verifies each member's CRC and catches truncated files.
        corrupt = z.testzip()
        if corrupt:
            errors.append('ZIP CRC failure: ' + corrupt)
    report['status'] = 'PASS' if not errors else 'FAIL'
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('zip_path')
    parser.add_argument('--expected-version', required=True)
    parser.add_argument('--json-report', help='write hashes and validation results')
    args = parser.parse_args()
    report = validate(args.zip_path, args.expected_version)
    if args.json_report:
        with open(args.json_report, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False, sort_keys=True)
            f.write('\n')
    print(report['status'] + ': packaged installation ' + args.zip_path)
    print(f"TOCs: {len(report['toc_files'])}; referenced files: {report['checked_includes']}; library fingerprints: {len(report['libraries_sha256'])}")
    for error in report['errors']:
        print('FAIL: ' + error)
    raise SystemExit(0 if report['status'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
