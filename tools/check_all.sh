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
    # 5a2. Guard ordering on chat entry points. This is a static check because the
    #      runtime harness cannot model it: a marked secret in wow_env.lua is an
    #      ordinary Lua string and comparing it succeeds there while it raises in
    #      game.
    printf '\n=== secret-guard ordering ===\n'
    python3 tools/secret_guard_audit.py || fail=1

    # 5b. Mention Manager end to end, in both client shapes. This is the check
    #     that would have caught 0.11.38: on a secret-value build the message
    #     filters are absent, so the highlight has to come from the render path.
    printf '\n=== mention manager (retail) ===\n'
    # No pipe: `cmd | tail` reports tail's exit status, which is always 0 and hid a
    # real probe failure once already.
    CHATIFY_STUB_MODE=retail lua5.1 tools/mention_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    printf '\n=== mention manager (classic) ===\n'
    CHATIFY_STUB_MODE=classic lua5.1 tools/mention_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    printf '\n=== history routing ===\n'
    lua5.1 tools/history_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    printf '\n=== copy window content ===\n'
    lua5.1 tools/copy_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    # 5c. Hooks on public Blizzard chat functions, driven with the argument shapes
    #     real third-party callers use.
    printf '\n=== blizzard hook signatures ===\n'
    lua5.1 tools/hook_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    # 5d. The taint that cannot be withdrawn: frame.AddMessage. Replacing it once on
    #     a 12.x client taints the field until /reload, and Blizzard reads it five
    #     lines before calling SetLastTellTarget on a secret whisper sender.
    printf '\n=== render hook taint (retail) ===\n'
    CHATIFY_STUB_MODE=retail lua5.1 tools/render_taint_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    printf '\n=== render hook taint (classic) ===\n'
    CHATIFY_STUB_MODE=classic lua5.1 tools/render_taint_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    # 5e. Proxy capture and parity. Also asserts the proxy stays unwired: running
    #     Blizzard's handler on a proxy alongside the real one would double history
    #     IDs, whisper sounds and tab flashes.
    printf '\n=== proxy capture (retail) ===\n'
    CHATIFY_STUB_MODE=retail lua5.1 tools/proxy_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    printf '\n=== proxy capture (classic) ===\n'
    CHATIFY_STUB_MODE=classic lua5.1 tools/proxy_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    # 5f. Slash commands are actually invoked. The load tests import every file, which
    #     proves the chunks compile; a wrong upvalue inside a function body survives
    #     that untouched. /chatifytrace was dead from 0.11.49 to 0.11.53 for exactly
    #     that reason and nothing in CI noticed.
    printf '\n=== slash commands (retail) ===\n'
    CHATIFY_STUB_MODE=retail lua5.1 tools/command_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    printf '\n=== slash commands (classic) ===\n'
    CHATIFY_STUB_MODE=classic lua5.1 tools/command_probe.lua > /tmp/chatify_probe.log 2>&1 || fail=1
    tail -2 /tmp/chatify_probe.log

    # 6. SavedVariables round-trip. A value the client cannot write costs the
    #    user every setting, because ChatifyDB and ChatifyHistoryDB share one
    #    file and one bad value discards both.
    printf '\n=== savedvariables ===\n'
    lua5.1 tools/savedvars_test.lua | tail -4 || fail=1

    # 7. The question a user actually asks: change a setting, log out, log back
    #    in, is it still there. Needs the real AceDB, since the behaviour under
    #    test is its removeDefaults pass. Skips itself if Ace3 is not available.
    printf '\n=== settings round trip ===\n'
    lua5.1 tools/roundtrip_test.lua | tail -4 || fail=1
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
