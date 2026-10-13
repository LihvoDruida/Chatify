#!/usr/bin/env python3
"""Allow publication only for newly created tags and unoccupied release assets.

GitHub's New Release form creates both the tag and an empty Release before
the tag-push workflow starts. That empty target is safe to populate once.
An existing release containing any asset is never eligible for republishing.
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


def check_no_existing_release(env: dict[str, str], tag: str, opener=urlopen) -> str:
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
            if resp.status != 200:
                raise ReleaseTagError(f'Unexpected GitHub Releases API status {resp.status}')
            # Creating a Release in the GitHub UI creates its tag first, then
            # triggers the push workflow. The Release can already exist before
            # our first step. Allow only that unoccupied target: the new-tag
            # event and checkout SHA are verified before this function runs.
            release = json.load(resp)
            if not isinstance(release, dict) or release.get('tag_name') != tag:
                raise ReleaseTagError(f'GitHub Release identity mismatch for {tag}')
            if release.get('draft') is not False or not release.get('published_at'):
                raise ReleaseTagError(f'GitHub Release {tag} must already be published, not a draft')
            if release.get('immutable') is True:
                raise ReleaseTagError(f'GitHub Release {tag} is immutable')
            if release.get('assets') != []:
                raise ReleaseTagError(f'GitHub Release {tag} already has assets; refusing to overwrite')
            return 'empty-existing-release' 
    except HTTPError as exc:
        if exc.code != 404:
            raise ReleaseTagError(f'GitHub Releases lookup failed: HTTP {exc.code}') from exc
        # 404 means the packager will create the release for this tag.
        return 'new-release'


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
        destination = check_no_existing_release(dict(os.environ), tag)
        print(f'PASS: newly created tag {tag}; target={destination}; no existing assets')
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError, ReleaseTagError) as exc:
        print(f'FAIL: release tag guard: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
