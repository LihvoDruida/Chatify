#!/usr/bin/env python3
"""The release AceDB test must extract real files and reject incomplete ZIPs."""
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

source = Path('tools/stage_acedb.py').resolve()
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    zpath = root / 'libraries.zip'
    dest = root / 'target'
    with zipfile.ZipFile(zpath, 'w') as z:
        z.writestr('Chatify/libs/AceDB-3.0/AceDB-3.0.lua', '--real AceDB sample')
        z.writestr('Chatify/libs/CallbackHandler-1.0/CallbackHandler-1.0.lua', '--real CallbackHandler sample')
        z.writestr('Chatify/irrelevant.txt', 'not extracted')
    result = subprocess.run([sys.executable, str(source), str(zpath), str(dest)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (dest / 'libs/AceDB-3.0/AceDB-3.0.lua').read_text() == '--real AceDB sample'
    assert not (dest / 'irrelevant.txt').exists()
    with zipfile.ZipFile(zpath, 'w') as z:
        z.writestr('Chatify/libs/AceDB-3.0/AceDB-3.0.lua', '--incomplete')
    reject = subprocess.run([sys.executable, str(source), str(zpath), str(root/'bad')], capture_output=True, text=True)
    assert reject.returncode != 0, 'missing CallbackHandler silently accepted'
print('R1-08 real AceDB staging required-file controls: PASS')
