#!/usr/bin/env python3
"""Rebuild the API baseline from a local checkout of Blizzard's Forever UI mirror.

Usage: python3 tools/update_forever_contracts.py /path/to/wow-ui-source --lua lua5.1
Only signatures are retained. Enum/default values are deliberately not extracted.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--lua', default='lua5.1')
    args = parser.parse_args()
    source = args.source.resolve()
    directory = source / 'Interface/AddOns/Blizzard_APIDocumentationGenerated'
    inputs = sorted(directory.glob('*.lua'))
    if not inputs:
        parser.error('generated API documentation missing from source checkout')
    result = subprocess.run([args.lua, str(ROOT / 'tools/extract_forever_contracts.lua'), *map(str, inputs)], capture_output=True, text=True, check=True)
    functions, events, errors = {}, {}, []
    for line in result.stdout.splitlines():
        fields = line.split('\t')
        if fields[0] == 'F':
            _, namespace, name, arguments, returns, system, filename, kind, secret = fields
            prefix = namespace + '.' if namespace else system + '.' if kind != 'System' else ''
            functions[prefix + name] = dict(arguments=arguments, returns=returns, system=system, file=filename, kind=kind, secret_arguments=secret)
        elif fields[0] == 'E':
            events[fields[1]] = dict(payload=fields[2], file=fields[3])
        else:
            errors.append(fields)
    if errors:
        raise SystemExit('Incomplete extraction: ' + repr(errors))
    sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    version = (source / 'version.txt').read_text().strip()
    hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    index = dict(source='https://github.com/Gethe/wow-ui-source', version=version, commit=sha,
                 signature_format='name:type:nilable:mixin; ... (enum/default values omitted)',
                 source_files_sha256=hashes, functions=functions, events=events)
    destination = ROOT / 'tools/fixtures/forever-70532.json'
    if version != '1.60.1.70532':
        raise SystemExit('Update snapshot filename, documentation and expected build before accepting a different client version: ' + version)
    destination.write_text(json.dumps(index, indent=2, sort_keys=True) + '\n')
    print(f'Forever API baseline: {len(functions)} functions, {len(events)} events, {len(inputs)} hashed source files; {version} {sha}')


if __name__ == '__main__':
    main()
