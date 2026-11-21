#!/usr/bin/env python3
"""Locale coverage: every literal key passed to a translation helper exists in
enUS, and enUS/ukUA define exactly the same keys.

Helpers recognised: T("..."), L("..."), ns.L("...") and L["..."] (SettingsWindow).
Only literal string arguments are checked; computed keys cannot be audited
statically. Run with --self-test to prove the audit catches each defect.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALES = ('enUS', 'ukUA')
KEY_RE = re.compile(r'''^\s*\[(["'])((?:\\.|(?!\1).)*)\1\]\s*=''', re.M)
USE_RE = re.compile(
    r'''\b(?:T|L|ns\.L)\(\s*(["'])((?:\\.|(?!\1).)*)\1\s*[),]'''
    r'''|\bL\[\s*(["'])((?:\\.|(?!\3).)*)\3\s*\]''')


def locale_keys(text: str) -> list[str]:
    return [m.group(2) for m in KEY_RE.finditer(text)]


def used_keys(sources: dict[str, str]) -> dict[str, set[str]]:
    used: dict[str, set[str]] = {}
    for name, text in sources.items():
        for m in USE_RE.finditer(text):
            key = m.group(2) if m.group(2) is not None else m.group(4)
            used.setdefault(key, set()).add(name)
    return used


def audit(sources: dict[str, str], locales: dict[str, str]) -> list[str]:
    errors = []
    tables = {}
    for code, text in locales.items():
        keys = locale_keys(text)
        dupes = sorted({k for k in keys if keys.count(k) > 1})
        if dupes:
            errors.append(f'{code}: duplicate keys: {dupes[:5]}')
        tables[code] = set(keys)
    en = tables['enUS']
    for code, keys in tables.items():
        if code == 'enUS':
            continue
        for key in sorted(en - keys):
            errors.append(f'{code}: missing translation: {key!r}')
        for key in sorted(keys - en):
            errors.append(f'{code}: key not in enUS: {key!r}')
    for key, files in sorted(used_keys(sources).items()):
        if key not in en:
            errors.append(f'{", ".join(sorted(files))}: key missing from enUS: {key!r}')
    return errors


def load_repo():
    sources = {p.name: p.read_text(encoding='utf-8') for p in sorted(ROOT.glob('*.lua'))}
    locales = {code: (ROOT / 'locale' / f'{code}.lua').read_text(encoding='utf-8') for code in LOCALES}
    return sources, locales


def self_test():
    sources, locales = load_repo()
    assert not audit(sources, locales), 'self-test needs a clean tree'
    cases = [
        ('code key missing', {**sources, 'Probe.lua': 'local x = T("Chatify locale audit probe")'}, locales,
         'key missing from enUS'),
        ('L[] key missing', {**sources, 'Probe.lua': "print(L['Chatify locale audit probe'])"}, locales,
         'key missing from enUS'),
        ('missing ukUA', sources, {**locales, 'enUS': locales['enUS'].replace(
            '})', '    ["Chatify audit only-en"] = "x",\n})', 1)}, 'missing translation'),
        ('extra ukUA', sources, {**locales, 'ukUA': locales['ukUA'].replace(
            '})', '    ["Chatify audit only-ua"] = "x",\n})', 1)}, 'key not in enUS'),
        ('duplicate', sources, {**locales, 'enUS': locales['enUS'].replace(
            '})', '    ["Profile Backup"] = "again",\n})', 1)}, 'duplicate keys'),
    ]
    for label, src, loc, expected in cases:
        errors = audit(src, loc)
        assert any(expected in e for e in errors), f'{label}: not detected ({errors[:3]})'
    print(f'locale audit negative controls: PASS ({len(cases)} cases)')


def main():
    if '--self-test' in sys.argv:
        self_test()
        return
    sources, locales = load_repo()
    errors = audit(sources, locales)
    for error in errors:
        print('FAIL: ' + error)
    if errors:
        sys.exit(1)
    en = locale_keys(locales['enUS'])
    print(f'locale audit: PASS ({len(used_keys(sources))} literal keys used in code; '
          f'{len(en)} keys in {"/".join(LOCALES)})')


if __name__ == '__main__':
    main()
