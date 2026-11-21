#!/usr/bin/env python3
"""Release workflow contract: source checks gate every tag publication.

validate runs tools/check_all.sh (real AceGUI mandatory), the real AceDB round
trip and the negative control on pushes to main, pull requests and tags.
release runs only for a pushed tag, needs validate, takes the version from the
triggering tag and publishes once with BigWigsMods/packager. Re-pushing a tag
is allowed and simply publishes again.
"""
from pathlib import Path
import re
import sys

source = Path('.github/workflows/package.yml').read_text(encoding='utf-8')


def job(name):
    match = re.search(rf'^  {name}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)', source, re.M | re.S)
    assert match, f'{name} job missing'
    return match.group(1)


def main():
    header = source.split('\njobs:\n', 1)[0]
    validate, release = job('validate'), job('release')

    # Triggers: main, pull requests and tags (alpha/beta tags excluded).
    assert re.search(r'^  pull_request:', header, re.M), 'pull requests are not validated'
    assert re.search(r'branches: \[main\]', header), 'pushes to main are not validated'
    assert re.search(r'^    tags:', header, re.M), 'tags do not trigger releases'
    assert '!**-alpha**' in header and '!**-beta**' in header, 'alpha/beta tags must not publish'
    assert re.search(r'^permissions:\n  contents: read', source, re.M), 'default token must be read-only'

    # validate: complete source gate, real libraries, no secrets.
    assert 'bash ./tools/check_all.sh' in validate, 'source gate missing'
    assert 'lua-check' in validate, 'luacheck (required by check_all.sh) is not installed in CI'
    assert 'CHATIFY_REQUIRE_REAL_ACEGUI: "1"' in validate, 'UI/UX tests could silently skip in CI'
    assert 'CHATIFY_REQUIRE_REAL_ACEDB: "1"' in validate and 'tools/roundtrip_test.lua' in validate
    assert 'tools/negative_control.sh' in validate, 'failure detection is not proven'
    assert 'ACE3_PATH=' in validate and 'ACE3_REF:' in source, 'Ace3 must be pinned and exported'
    assert 'secrets.' not in validate, 'validation must not see publication secrets'

    # release: tag-only, gated, single publish, version from the triggering tag.
    assert re.search(r'^    needs: validate$', release, re.M), 'release bypasses validation'
    condition = re.search(r'^    if: ([^\n]+)', release, re.M)
    assert condition, 'release event guard missing'
    for token in ("github.event_name == 'push'", "startsWith(github.ref, 'refs/tags/')"):
        assert token in condition[1], f'release guard missing: {token}'
    assert 'contents: write' in release, 'release needs write access for GitHub Releases'
    assert release.count('uses: BigWigsMods/packager@v2') == 1, 'expected exactly one package-and-publish'
    assert 'CF_API_KEY: ${{ secrets.CF_API_KEY }}' in release
    assert 'GITHUB_REF_NAME#v' in release, 'TOC versions must come from the triggering tag'
    assert 'git describe' not in source, 'version inferred from an unrelated tag'
    assert 'tools/generate_tocs.py --check' in release, 'flavor TOCs not verified after version sync'
    assert release.index('Update Version in .toc Files') < release.index('BigWigsMods/packager@v2')
    print('Release workflow: PASS (validate on main/PR/tag, tag-only release needs validate, '
          'tag version, single publish)')


if __name__ == '__main__':
    try:
        main()
    except AssertionError as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        sys.exit(1)
