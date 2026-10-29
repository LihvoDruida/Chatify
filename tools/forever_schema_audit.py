#!/usr/bin/env python3
"""Check every C_* reference in addon modules against the pinned Forever API schema.

Presence in generated docs proves the name/signature is documented in that source
build, not that an API call is allowed by the live client's security context.
"""
import argparse
import json
from pathlib import Path
import re
from lua_source import mask_lua

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = re.compile(r'\b(C_[A-Za-z0-9_]+)\.([A-Za-z0-9_]+)')


def audit():
    baseline = json.loads((ROOT / 'tools/fixtures/forever-70532.json').read_text())
    functions, events = baseline['functions'], baseline['events']
    references = {}
    used_events = set()
    errors = []
    for path in sorted(ROOT.glob('*.lua')):
        source = path.read_text(encoding='utf-8')
        code = mask_lua(source, strings=True)
        for match in REFERENCE.finditer(code):
            name = '.'.join(match.groups())
            location = f'{path.name}:{code.count(chr(10), 0, match.start()) + 1}'
            references.setdefault(name, []).append(location)
            if name not in functions:
                errors.append(f'{location}: {name} absent from Forever baseline; add an explicit optional-client decision before using it')
        for token in set(re.findall(r'\b[A-Z][A-Z0-9_]+\b', mask_lua(source))):
            if token in events:
                used_events.add(token)
    # A dynamic namespace hook is intentionally named by string, not a direct call.
    references.setdefault('C_ChatInfo.SwapChatChannelsByChannelIndex', ['Config.lua:InstallChannelStateHooks (dynamic hook)'])
    if 'C_ChatInfo.SwapChatChannelsByChannelIndex' not in functions:
        errors.append('dynamic channel hook absent from Forever baseline')
    return dict(version=baseline['version'], commit=baseline['commit'],
                documented_function_count=len(functions), documented_event_count=len(events),
                namespace_references={name: dict(locations=places, contract=functions.get(name)) for name, places in sorted(references.items())},
                used_documented_events=sorted(used_events),
                legacy_optional_events=['CHAT_MSG_BN_CONVERSATION'],
                errors=errors)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json-report')
    args = parser.parse_args()
    report = audit()
    if args.json_report:
        Path(args.json_report).write_text(json.dumps(report, indent=2) + '\n')
    for error in report['errors']:
        print('FAIL: ' + error)
    if report['errors']:
        raise SystemExit(1)
    print(f"Forever schema audit: PASS ({len(report['namespace_references'])} C_* references, {len(report['used_documented_events'])} documented events; source {report['version']})")
    print('Scope: documented names/contracts; call semantics covered by forever_api_probe.lua, security requires live-client verification.')


if __name__ == '__main__':
    main()
