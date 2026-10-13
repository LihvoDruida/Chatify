#!/usr/bin/env python3
"""Reject non-new-tag events and any tag whose GitHub Release already exists.

Called only in the release job, before package downloads or publication.
An authorized GitHub API call is required; network/auth failures are fatal.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen


class ReleaseTagError(RuntimeError):
    pass


def check_event(env: dict[str, str], event: dict) -> str:
    tag = env.get('GITHUB_REF_NAME', '')
    if env.get('GITHUB_EVENT_NAME') != 'push':
        raise ReleaseTagError('Publishing requires a push event (manual runs cannot publish)')
    if env.get('GITHUB_REF_TYPE') != 'tag' or env.get('GITHUB_REF') != f'refs/tags/{tag}':
        raise ReleaseTagError('Publishing requires the triggering Git tag ref')
    if event.get('created') is not True or event.get('deleted') is True:
        raise ReleaseTagError('Only creation of a new tag can publish; tag updates are rejected')
    if not re.fullmatch(r'v?[0-9]+(?:\.[0-9]+){1,3}(?:-[0-9A-Za-z.-]+)?', tag):
        raise ReleaseTagError('Tag must contain a valid release version')
    if not env.get('GITHUB_REPOSITORY', '') or '/' not in env['GITHUB_REPOSITORY']:
        raise ReleaseTagError('Missing GitHub repository identity')
    return tag


def check_no_existing_release(env: dict[str, str], tag: str, opener=urlopen) -> None:
    api = env.get('GITHUB_API_URL', 'https://api.github.com').rstrip('/')
    repo = env['GITHUB_REPOSITORY']
    token = env.get('GITHUB_TOKEN', '')
    if not token:
        raise ReleaseTagError('GitHub token missing; cannot verify if tag was published')
    req = Request(
        f"{api}/repos/{quote(repo, safe='/')}/releases/tags/{quote(tag, safe='')}",
        headers={'Authorization': f'Bearer {token}',
                 'Accept': 'application/vnd.github+json',
                 'X-GitHub-Api-Version': '2022-11-28'},
    )
    try:
        with opener(req, timeout=20) as resp:
            if resp.status == 200:
                raise ReleaseTagError(f'Release already exists for {tag}; refusing to republish')
            raise ReleaseTagError(f'Unexpected GitHub Releases API status {resp.status}')
    except HTTPError as exc:
        if exc.code != 404:
            raise ReleaseTagError(f'GitHub Releases lookup failed: HTTP {exc.code}') from exc
        # 404 means no GitHub Release for this tag; continue on the same tag event.


def check_checkout_matches_tag(env: dict[str, str], tag: str) -> None:
    # Handles lightweight and annotated tags. Reject ref substitution.
    expected = env.get('GITHUB_SHA', '')
    actual = subprocess.run(['git', 'rev-parse', f'refs/tags/{tag}^{{commit}}'],
                            text=True, capture_output=True, check=True).stdout.strip()
    if actual != expected:
        raise ReleaseTagError(f'Tag commit {actual} does not match trigger {expected}')


def main() -> int:
    try:
        event_path = os.environ.get('GITHUB_EVENT_PATH', '')
        if not event_path:
            raise ReleaseTagError('Missing webhook event payload')
        event = json.loads(Path(event_path).read_text(encoding='utf8'))
        tag = check_event(dict(os.environ), event)
        check_checkout_matches_tag(dict(os.environ), tag)
        check_no_existing_release(dict(os.environ), tag)
        print(f'PASS: newly created tag {tag}; no prior GitHub Release')
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError, ReleaseTagError) as exc:
        print(f'FAIL: release tag guard: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
