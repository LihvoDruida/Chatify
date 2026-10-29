#!/usr/bin/env python3
"""Verify source gates and pre-publication validation stay in the release path."""
from pathlib import Path
import re

source = Path('.github/workflows/package.yml').read_text(encoding='utf-8')
validation, release = source.split('\n  release:\n', 1)
assert re.search(r'^  validate:\s*$', validation, re.M)
condition = re.search(r'^    if: ([^\n]+)', release, re.M)
assert condition, 'release event guard missing'
for token in ("github.event_name == 'push'", 'github.event.created == true', "startsWith(github.ref, 'refs/tags/')"):
    assert token in condition[1], f'tag event guard missing: {token}'
assert 'needs: validate' in release, 'release bypasses source validation'
assert 'tools/check_all.sh' in validation
assert 'CF_API_KEY' not in validation and 'GITHUB_OAUTH' not in validation
assert 'contents: read' in source and 'contents: write' in release
assert release.count('uses: BigWigsMods/packager@v2') == 2, 'expected build-only then guarded publish'
assert 'args: -d' in release and 'args: -c -e -o' in release
assert 'GITHUB_REF_NAME#v' in release and "-name '*.toc'" in release
for token in ('tools/release_tag_guard.py', 'tools/validate_package.py', '--expected-version',
              'CHATIFY_APPROVED_ZIP', 'CHATIFY_APPROVED_SHA256', 'CHATIFY_ZIP_GUARD_RECEIPT',
              'chmod +x tools/release-guards/zip', '$GITHUB_PATH'):
    assert token in release, f'missing release protection: {token}'
assert release.index('tools/release_tag_guard.py') < release.index('args: -d')
assert release.index('tools/validate_package.py') < release.index('args: -c -e -o')
assert release.index('CF_API_KEY:') > release.index('args: -c -e -o'), 'credentials exposed during dry run'
assert 'git describe' not in release, 'release version inferred from unrelated tag'
print('Release workflow: PASS (source gate, fresh tag, validated ZIP, digest-bound publish)')
