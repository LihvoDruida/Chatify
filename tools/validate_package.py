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
import stat
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
        normalized = [n.casefold() for n in names]
        if len(normalized) != len(set(normalized)):
            errors.append('ZIP contains paths that collide on case-insensitive filesystems')
        for info in z.infolist():
            if stat.S_ISLNK(info.external_attr >> 16):
                errors.append('ZIP contains symlink: ' + info.filename)
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
                tag = element.tag.rsplit('}', 1)[-1].lower()
                if tag not in ('script', 'include'):
                    continue
                value = element.attrib.get('file')
                if not value:
                    errors.append(f'Empty {tag} in {filepath}')
                    continue
                file_ref = posixpath.normpath(posixpath.join(posixpath.dirname(filepath), value.replace('\\', '/')))
                if not file_ref.startswith('Chatify/') or file_ref not in files:
                    errors.append(f'Unresolved {filepath} -> {file_ref}')
                elif tag == 'include':
                    inspect_xml(file_ref)
                report['checked_includes'] += 1

        interfaces_by_toc = {}
        for toc in tocs:
            data = z.read(toc).decode('utf-8-sig', 'replace')
            interface_headers = re.findall(r'^## Interface:\s*(.*?)\s*$', data, re.M)
            if len(interface_headers) != 1 or not re.fullmatch(r'[0-9]+(?:,\s*[0-9]+)*', interface_headers[0]):
                errors.append(f'{toc}: invalid or missing Interface metadata')
            else:
                interfaces = [value.strip() for value in interface_headers[0].split(',')]
                interfaces_by_toc[toc] = set(interfaces)
                if len(interfaces) != len(set(interfaces)):
                    errors.append(f'{toc}: duplicate Interface targets')
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
        generic = interfaces_by_toc.get('Chatify/Chatify.toc', set())
        for toc, interfaces in interfaces_by_toc.items():
            if not interfaces.issubset(generic):
                errors.append(f'{toc}: interfaces missing from generic TOC')
        required_assets = (
            'assets/icon.blp', 'assets/icons/CopyChat.png', 'assets/icons/HistoryChat.png',
            'assets/icons/SettingsCog.png', 'assets/alert/notification-0.ogg',
            'assets/themes/gw2/chatframebackground.png', 'assets/themes/gw2/chatframeborder.png',
            'assets/themes/gw2/channel_button_normal.png', 'assets/themes/gw2/channel_button_normal_highlight.png',
            'assets/themes/gw2/channel_button_vc.png', 'assets/themes/gw2/channel_button_vc_highlight.png',
        )
        config_path = 'Chatify/Config.lua'
        if config_path in files:
            bound_fonts = re.findall(r'ADDON_FONT_ROOT\s*\.\.\s*"([^"]+)"', z.read(config_path).decode('utf-8-sig'))
            required_assets += tuple('assets/Fonts/' + font for font in bound_fonts)
        for asset in required_assets:
            name = 'Chatify/' + asset
            if name not in files or z.getinfo(name).file_size == 0:
                errors.append('Missing/empty required asset: ' + name)
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
            if name.startswith(('Chatify/tools/', 'Chatify/.git/', 'Chatify/.github/')):
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
