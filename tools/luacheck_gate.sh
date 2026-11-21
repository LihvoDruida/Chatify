#!/usr/bin/env bash
# Static analysis gate: the whole addon must be luacheck-clean under
# .luacheckrc, and that config must still catch the defects it exists for.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v luacheck >/dev/null || { echo 'FAIL luacheck not installed (apt-get install lua-check)' >&2; exit 2; }

luacheck . --no-color --quiet --codes

# Negative controls: each snippet must be rejected by the same configuration.
expect_reject() {
    local label=$1 code=$2 snippet=$3
    local out
    if out=$(printf '%s\n' "$snippet" | luacheck --config .luacheckrc --no-color --codes --filename ChatProbe.lua - 2>&1); then
        echo "FAIL luacheck accepted: $label" >&2; exit 1
    fi
    grep -q "($code)" <<<"$out" || { echo "FAIL luacheck missed $code for: $label" >&2; echo "$out" >&2; exit 1; }
}
expect_reject 'misspelled WoW API'      W113 'local f = CreateFrmae("Frame")'
expect_reject 'new global write'        W111 'ChatifyLeak = true'
expect_reject 'mutating read-only API'  W122 'C_Timer.After = nil'
expect_reject 'unused local'            W211 'local _, ns = ...; local unused = ns'
expect_reject 'unused local function'   W211 'local function Dead() end'
echo 'luacheck gate: PASS (clean tree; 5 negative controls rejected)'
