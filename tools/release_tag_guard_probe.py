#!/usr/bin/env python3
"""Offline regression for strict new-tag-only publication controls."""
from __future__ import annotations

import json
import subprocess
import tempfile
import os
from pathlib import Path
from urllib.error import HTTPError

from release_tag_guard import ReleaseTagError, check_event, check_no_existing_release, check_checkout_matches_tag

workflow = Path('.github/workflows/package.yml').read_text(encoding='utf8')
job = workflow.split('\n  release:\n', 1)[1]
release_condition = job.split('\n    if:', 1)[1].split('\n', 1)[0]
for required in ["github.event_name == 'push'", 'github.event.created == true',
                 "startsWith(github.ref, 'refs/tags/')"]:
    assert required in release_condition, f'Release job condition missing: {required}'
assert 'chmod +x tools/release-guards/zip' in job, 'wrapper executable bit not repaired in release job'
assert 'tools/release_tag_guard.py' in job, 'tag guard missing'
assert 'v[0-9]*' in workflow and '[0-9]*' in workflow, 'unrestricted tag triggers' 

base = dict(GITHUB_EVENT_NAME='push', GITHUB_REF_TYPE='tag', GITHUB_REF='refs/tags/v2.19.0',
            GITHUB_REF_NAME='v2.19.0', GITHUB_REPOSITORY='LihvoDruida/Chatify',
            GITHUB_TOKEN='test-token')
assert check_event(base, {'created': True, 'deleted': False}) == 'v2.19.0'

for changes, event in [
    ({'GITHUB_EVENT_NAME': 'workflow_dispatch'}, {'created': True}),
    ({'GITHUB_EVENT_NAME': 'pull_request'}, {'created': True}),
    ({'GITHUB_REF': 'refs/heads/main', 'GITHUB_REF_TYPE': 'branch', 'GITHUB_REF_NAME': 'main'}, {'created': True}),
    ({}, {'created': False}),
    ({}, {'created': False, 'deleted': False, 'forced': True}),
    ({}, {'created': True, 'deleted': True}),
    ({'GITHUB_REF_NAME': 'release-bogus', 'GITHUB_REF': 'refs/tags/release-bogus'}, {'created': True}),
]:
    env = base | changes
    try:
        check_event(env, event)
    except ReleaseTagError:
        pass
    else:
        raise AssertionError(f'Unexpected release permission: {changes} / {event}')

class FakeResponse:
    def __init__(self, status):
        self.status = status
    def __enter__(self):
        return self
    def __exit__(self, *_):
        return False

def fake_new(request, timeout):
    assert request.full_url.endswith('/repos/LihvoDruida/Chatify/releases/tags/v2.19.0')
    raise HTTPError(request.full_url, 404, 'Not Found', {}, None)

check_no_existing_release(base, 'v2.19.0', fake_new)

def fake_existing(request, timeout):
    return FakeResponse(200)

try:
    check_no_existing_release(base, 'v2.19.0', fake_existing)
except ReleaseTagError:
    pass
else:
    raise AssertionError('Existing release was accepted')

def fake_error(request, timeout):
    raise HTTPError(request.full_url, 403, 'Forbidden', {}, None)

try:
    check_no_existing_release(base, 'v2.19.0', fake_error)
except ReleaseTagError:
    pass
else:
    raise AssertionError('API error was treated as an absent release')

# Verify that both lightweight and annotated tags identify the same commit
# and that an altered commit SHA cannot pass the checkout check.
with tempfile.TemporaryDirectory() as tmp:
    workdir = Path(tmp)
    subprocess.run(['git', 'init', '-q', str(workdir)], check=True)
    subprocess.run(['git', '-C', str(workdir), 'config', 'user.email', 'ci@localhost'], check=True)
    subprocess.run(['git', '-C', str(workdir), 'config', 'user.name', 'CI'], check=True)
    (workdir / 'test.txt').write_text('source')
    subprocess.run(['git', '-C', str(workdir), 'add', 'test.txt'], check=True)
    subprocess.run(['git', '-C', str(workdir), 'commit', '-qm', 'test'], check=True)
    commit = subprocess.check_output(['git', '-C', str(workdir), 'rev-parse', 'HEAD'], text=True).strip()
    subprocess.run(['git', '-C', str(workdir), 'tag', 'v2.19.0'], check=True)
    subprocess.run(['git', '-C', str(workdir), 'tag', '-a', 'v2.19.1', '-m', 'annotated'], check=True)
    previous = Path.cwd()
    os.chdir(workdir)
    try:
        for tag in ('v2.19.0', 'v2.19.1'):
            check_checkout_matches_tag({'GITHUB_SHA': commit}, tag)
        try:
            check_checkout_matches_tag({'GITHUB_SHA': '0' * 40}, 'v2.19.1')
        except ReleaseTagError:
            pass
        else:
            raise AssertionError('Mismatched tag SHA accepted')
    finally:
        os.chdir(previous)

print('Fresh-tag release gating: PASS (new tag, branch, PR, manual, force update, existing release, API failure)')
