#!/usr/bin/env python3
"""Source-CI regression: publishing is lean, tag-only, and uses tag TOC versions."""
from pathlib import Path
import re

source = Path('.github/workflows/package.yml').read_text(encoding='utf-8')
assert re.search(r'^  validate:\s*$', source, re.M), 'source CI missing'
assert re.search(r'^  release:\s*$', source, re.M), 'tag release job missing'
validation, release = source.split('\n  release:\n', 1)
condition = re.search(r'^    if: ([^\n]+)', release, re.M)
assert condition, 'release event guard missing'
for token in ("github.event_name == 'push'", 'github.event.created == true',
              "startsWith(github.ref, 'refs/tags/')"):
    assert token in condition.group(1), f'tag event guard missing: {token}'
assert 'needs: validate' not in release, 'release must not depend on slow source tests'
assert 'if: ${{ github.event_name != ' in validation, 'source CI must skip tags'
assert 'uses: BigWigsMods/packager@v2' in release
assert release.count('uses: BigWigsMods/packager@v2') == 1, 'duplicate packaging/publishing'
assert 'args: -d' not in release, 'debug-only packaging cannot publish'
assert 'args: -c' not in release, 'rebuild/repack is unnecessary'
assert 'GITHUB_REF_NAME#v' in release, 'TOC versions must come from triggering tag'
assert 'find . -maxdepth 1' in release and '-name \'*.toc\'' in release
assert 'CF_API_KEY:' in release and 'GITHUB_OAUTH:' in release, 'publication credentials missing'
for forbidden in ('release_tag_guard.py', 'real packaged AceDB', 'roundtrip_test.lua',
                  'stage_acedb.py', 'validate_package.py', 'CHATIFY_APPROVED_SHA256',
                  'release-guards', 'upload-artifact@v4', 'git-cliff-action',
                  'sudo apt-get', 'tools/check_all.sh'):
    assert forbidden.lower() not in release.lower(), f'extra release check: {forbidden}'
assert 'tools/check_all.sh' in validation, 'keep regression checks on commits/PRs'
print('PASS: one package-and-publish action, new-tag-only, tag TOC versions, source CI separate')
