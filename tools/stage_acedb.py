#!/usr/bin/env python3
"""Extract ONLY the packaged AceDB and CallbackHandler source for Lua fixture QA.

The test then runs the real AceDB implementation from the very ZIP being
released; it does not use external dependencies from the SOURCE checkout.
"""
from pathlib import Path
import argparse
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('zip_path')
parser.add_argument('destination')
args = parser.parse_args()
root = Path(args.destination).resolve()
count = 0
with zipfile.ZipFile(args.zip_path) as z:
    for info in z.infolist():
        if info.is_dir():
            continue
        for lib in ('AceDB-3.0', 'CallbackHandler-1.0'):
            prefix = f'Chatify/libs/{lib}/'
            if info.filename.startswith(prefix):
                rel = Path(info.filename.removeprefix('Chatify/'))
                target = (root / rel).resolve()
                if root not in target.parents:
                    raise SystemExit('unsafe archive path')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(info))
                count += 1
                break
if count < 2:
    raise SystemExit(f'ERROR: only {count} AceDB/CallbackHandler source files extracted')
for required in ('AceDB-3.0/AceDB-3.0.lua', 'CallbackHandler-1.0/CallbackHandler-1.0.lua'):
    if not (root / 'libs' / required).is_file():
        raise SystemExit('missing real library: ' + required)
print(f'Staged {count} actual packaged library files at {root / "libs"}')
