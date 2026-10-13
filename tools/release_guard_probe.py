#!/usr/bin/env python3
"""Regression check: reject changed/replaced ZIP bytes before any upload."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile

WRAPPER = str(Path('tools/release-guards/zip').resolve())

def run(*args: str, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([WRAPPER, *args], env=env, text=True,
                          capture_output=True, check=False)

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    addon = root / 'Chatify'
    addon.mkdir()
    (addon / 'Chatify.toc').write_text('## Version: 9.9.9\n', encoding='utf8')
    zipfile = root / 'Chatify-9.9.9.zip'
    subprocess.run(['/usr/bin/zip', '-X', '-r', str(zipfile), 'Chatify'],
                   cwd=root, check=True, capture_output=True)
    approved = hashlib.sha256(zipfile.read_bytes()).hexdigest()
    receipt = root / 'approved.receipt'
    env = dict(os.environ, CHATIFY_APPROVED_ZIP=str(zipfile),
               CHATIFY_APPROVED_SHA256=approved,
               CHATIFY_ZIP_GUARD_RECEIPT=str(receipt))

    valid = subprocess.run([WRAPPER, '-X', '-r', str(zipfile), 'Chatify'],
                           cwd=root, env=env, text=True, capture_output=True)
    assert valid.returncode == 0, valid.stdout + valid.stderr
    assert receipt.exists(), 'missing byte-identity receipt'
    assert approved in receipt.read_text()

    receipt.unlink()
    (addon / 'Chatify.toc').write_text('## Version: 0.0.0\n', encoding='utf8')
    changed = subprocess.run([WRAPPER, '-X', '-r', str(zipfile), 'Chatify'],
                             cwd=root, env=env, text=True, capture_output=True)
    assert changed.returncode == 53, changed.stdout + changed.stderr
    assert not receipt.exists(), 'mismatched package got a receipt'
    assert not zipfile.exists(), 'unapproved ZIP survived upstream existence check'

    foreign = run('-X', '-r', str(root / 'different.zip'), str(addon), env=env)
    assert foreign.returncode == 52, foreign.stdout + foreign.stderr
    missing = run('-X', '-r', str(zipfile), str(addon), env=dict(os.environ))
    assert missing.returncode != 0

print('R1-08 release SHA guard: PASS (exact match, modified ZIP, foreign path, missing approval)')
