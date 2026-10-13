#!/usr/bin/env bash
# Break the real R1-01 regression deliberately; it MUST fail.
set -euo pipefail
cd "$(dirname "$0")/.."
file=ProfileTransfer.lua
backup=$(mktemp)
cp "$file" "$backup"
restore() { cp "$backup" "$file"; rm -f "$backup"; }
trap restore EXIT
python3 - <<'PY'
from pathlib import Path
p=Path('ProfileTransfer.lua')
s=p.read_text()
assert 'local MAX_ENTRIES = 10000' in s
p.write_text(s.replace('local MAX_ENTRIES = 10000', 'local MAX_ENTRIES = 20000', 1))
PY
if lua5.1 tools/profile_integrity_probe.lua > /tmp/chatify_negative_control.log 2>&1; then
  cat /tmp/chatify_negative_control.log
  echo 'FAIL: a deliberate regression did not turn tests red' >&2
  exit 1
fi
echo 'PASS: deliberate profile regression was caught (expected failing test)'
