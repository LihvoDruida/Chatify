#!/usr/bin/env bash
# Every check, in one place. Run before every release.
#
#   ./tools/check_all.sh
#
# Exits non-zero on the first failure so it can be wired into CI directly.

set -u
cd "$(dirname "$0")/.."

fail=0
step() {
    printf '\n=== %s ===\n' "$1"
    shift
    if "$@"; then
        return 0
    fi
    fail=1
    return 1
}

# 1. Syntax. Catches nothing subtle, but catches typos instantly.
printf '\n=== lua syntax ===\n'
if command -v luac5.1 >/dev/null 2>&1; then
    if luac5.1 -p ./*.lua locale/*.lua; then
        rm -f luac.out
        echo "all files parse"
    else
        rm -f luac.out
        fail=1
    fi
else
    echo "luac5.1 not installed, skipped"
fi

# 2. Symbols. Valid Lua that resolves to nil at runtime.
step "symbol check" python3 tools/check_symbols.py

# 3. Deeper static audit: shadowed keys, missing handlers, dead references.
step "static audit" python3 tools/audit.py

# 4. TOC files regenerated from Chatify.toc and in version sync.
step "toc freshness" python3 tools/generate_tocs.py --check

# 5. The real test: load every file and drive the hot paths, in both client
#    shapes. Classic has no secret-value API; retail has one, and asserts that a
#    secret payload comes back byte-identical.
if command -v lua5.1 >/dev/null 2>&1; then
    printf '\n=== load test (classic) ===\n'
    CHATIFY_STUB_MODE=classic lua5.1 tools/stub/load_test.lua | tail -3 || fail=1

    printf '\n=== load test (retail, secret values) ===\n'
    CHATIFY_STUB_MODE=retail lua5.1 tools/stub/load_test.lua | tail -3 || fail=1
else
    printf '\n=== load test ===\nlua5.1 not installed, skipped\n'
fi

printf '\n%s\n' "----------------------------------------"
if [ "$fail" -eq 0 ]; then
    echo "All checks passed."
else
    echo "FAILURES above."
fi
exit "$fail"
