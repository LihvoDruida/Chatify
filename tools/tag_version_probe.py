#!/usr/bin/env python3
"""Exercise the real release workflow TOC sync step against stale local versions.

The version must be resolved exclusively from the triggering Git tag (with or
without an initial v); source TOC versions do not need to equal the tag.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / '.github/workflows/package.yml'
TOCS = sorted(ROOT.glob('*.toc'))


def extract_run(step_name):
    lines = WORKFLOW.read_text(encoding='utf-8').splitlines()
    heading = '      - name: ' + step_name
    try:
        start = lines.index(heading)
    except ValueError:
        raise AssertionError(f'Workflow step missing: {step_name}')
    for index in range(start + 1, len(lines)):
        if lines[index] == '        run: |':
            break
        if lines[index].startswith('      - name: '):
            raise AssertionError(f'No run block for {step_name}')
    else:
        raise AssertionError(f'No run block for {step_name}')
    body = []
    for line in lines[index + 1:]:
        if line and not line.startswith('          '):
            break
        body.append(line[10:] if line else '')
    if not body:
        raise AssertionError(f'Empty run block for {step_name}')
    return '\n'.join(body) + '\n'


def main():
    assert len(TOCS) >= 8, 'Expected all main and flavor TOCs'
    sync = extract_run('Update Version in .toc Files')
    assert 'GITHUB_REF_NAME' in sync, 'Version must come from the triggering Git tag'
    assert 'git describe' not in sync
    original = {p.name: p.read_bytes() for p in TOCS}
    for tag, expected in [('v9.8.7', '9.8.7'), ('10.11.12', '10.11.12')]:
        with tempfile.TemporaryDirectory(prefix='chatify_tag_version_') as tmp:
            temp = Path(tmp)
            for number, toc in enumerate(TOCS):
                text = toc.read_text(encoding='utf-8')
                text = re.sub(r'^## Version: .*$', f'## Version: 0.0.{number}', text, flags=re.MULTILINE)
                (temp / toc.name).write_text(text, encoding='utf-8')
            (temp / 'tools').mkdir()
            shutil.copyfile(ROOT / 'tools/generate_tocs.py', temp / 'tools/generate_tocs.py')
            # Pre-tag validation must not fail just because flavor TOCs have
            # different developer versions; post-tag strict check still applies.
            subprocess.run([sys.executable, 'tools/generate_tocs.py', '--check', '--ignore-version'], cwd=temp, check=True, capture_output=True)
            strict_before = subprocess.run([sys.executable, 'tools/generate_tocs.py', '--check'], cwd=temp, capture_output=True)
            assert strict_before.returncode != 0, 'Pre-tag versions must genuinely differ'
            env = dict(os.environ, GITHUB_REF_TYPE='tag', GITHUB_REF_NAME=tag)
            subprocess.run(['bash', '-euo', 'pipefail', '-c', sync], cwd=temp, env=env, check=True, capture_output=True, text=True)
            for toc in TOCS:
                lines = (temp / toc.name).read_text(encoding='utf-8').splitlines()
                versions = [line for line in lines if line.startswith('## Version:')]
                assert versions == [f'## Version: {expected}'], (tag, toc.name, versions)
            print(f'PASS: {tag} overrides all {len(TOCS)} stale local TOC versions')
    with tempfile.TemporaryDirectory(prefix='chatify_tag_invalid_') as tmp:
        env = dict(os.environ, GITHUB_REF_TYPE='tag', GITHUB_REF_NAME='release-main')
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', sync], cwd=tmp, env=env, capture_output=True)
        assert result.returncode != 0, 'Invalid tag must be rejected'
    assert all(toc.read_bytes() == original[toc.name] for toc in TOCS), 'Source TOCs unexpectedly modified'
    print('PASS: invalid release tag rejected; source TOCs unchanged')


if __name__ == '__main__':
    try:
        main()
    except (AssertionError, subprocess.CalledProcessError) as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
