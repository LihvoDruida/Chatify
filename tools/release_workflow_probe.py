#!/usr/bin/env python3
"""Ensure release is checked before upload and never refetches externals."""
from pathlib import Path
import re

source = Path('.github/workflows/package.yml').read_text(encoding='utf-8')
assert re.search(r'^  validate:\s*$', source, re.M), 'required source validation absent'
assert re.search(r'^  release:\s*$', source, re.M), 'release job absent'
assert not re.search(r'^  (package-preflight|build):\s*$', source, re.M), 'independent rebuild job exists'
steps = re.findall(r'^      - name: ([^\n]+)', source, re.M)
expected = [
    'Update Version in .toc Files',
    'Generate release changelog BEFORE packaging',
    'Build full candidate ZIP without publishing',
    'Validate ZIP and record approval hash',
    'Real embedded AceDB persistence regression',
    'Require publication credentials',
    'Activate guarded ZIP executable',
    'Publish only SHA-approved artifact; never refetch externals',
    'Verify pre-upload guard was actually called',
]
pos = [steps.index(label) for label in expected]
assert pos == sorted(pos), 'release steps ordered incorrectly'
assert source.count('uses: BigWigsMods/packager@v2') == 2, 'expected preview and reuse only'
assert re.search(r'args: -d\s*$', source, re.M), 'preview must never publish'
assert re.search(r'args: -c -e -o\s*$', source, re.M), 'publication must reuse source and externals'
assert 'CHATIFY_APPROVED_SHA256' in source, 'pre-approved ZIP hash missing'
assert 'CHATIFY_ZIP_GUARD_RECEIPT' in source, 'ZIP guard receipt missing'
assert 'CHATIFY_REQUIRE_REAL_ACEDB=1' in source, 'real AceDB must not silently skip'
assert 'GITHUB_PATH' in source, 'guard interception not installed'
assert 'CF_API_KEY' in source, 'CurseForge token missing'
assert 'GITHUB_REF_NAME' in source, 'tag-controlled release missing'
assert "github.event_name == 'push'" in source, 'manual run may trigger publishing'
assert 'github.event.created == true' in source, 'tag update or branch push could publish'
assert 'tools/release_tag_guard.py' in source, 'fresh-tag guard missing'
assert 'chmod +x tools/release-guards/zip' in source, 'zip guard may not be executable after checkout'

print('R1-08 single-job source -> ZIP -> validate -> AceDB -> SHA-check -> publish contract: PASS')
