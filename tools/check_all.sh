#!/usr/bin/env bash
# Required source validation. Every missing dependency and failed check is fatal.
# Packaged libraries and live WoW validation are separate gates (R1-08).
set -euo pipefail
cd "$(dirname "$0")/.."

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'FAIL required dependency unavailable: %s\n' "$1" >&2
        exit 2
    fi
}
require python3

passed=0
optional_skips=0
run() {
    local label=$1
    shift
    printf '\n=== REQUIRED: %s ===\n' "$label"
    local logfile
    logfile=$(mktemp)
    if ! "$@" > "$logfile" 2>&1; then
        cat "$logfile"
        rm -f "$logfile"
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
    cat "$logfile"
    if grep -Eq '(^|[[:space:]])FAIL([[:space:]:]|$)' "$logfile"; then
        rm -f "$logfile"
        printf 'FAIL: required test printed a failure: %s\n' "$label" >&2
        exit 1
    fi
    if grep -Eq '(^|[[:space:]])SKIP([[:space:](]|$)' "$logfile"; then
        rm -f "$logfile"
        printf 'FAIL: required test SKIP: %s\n' "$label" >&2
        exit 1
    fi
    rm -f "$logfile"
    printf 'PASS: %s\n' "$label"
    passed=$((passed+1))
}

# Python audits intentionally run outside the Lua fixture loop.
run "symbols" python3 tools/check_symbols.py
run "static audit" python3 tools/audit.py
run "secret guard audit" python3 tools/secret_guard_audit.py
run "TOC consistency (release versions set by tag)" python3 tools/generate_tocs.py --check --ignore-version
run "tag-driven release TOC metadata" python3 tools/tag_version_probe.py
run "R1-08 package validator negative controls" python3 tools/package_validation_probe.py
run "R1-08 same-ZIP release workflow gate" python3 tools/release_workflow_probe.py
run "R1-08 real AceDB staging control" python3 tools/stage_acedb_probe.py
run "R1-08 publication SHA-256 guard syntax" bash -n tools/release-guards/zip
run "R1-08 publication SHA-256 guard negatives" python3 tools/release_guard_probe.py
# Python audits above run even when Lua is unavailable. Missing Lua is then
# a hard failure (never a green partial suite).
require luac5.1
require lua5.1
run "Lua 5.1 parser" luac5.1 -p ./*.lua locale/*.lua

for mode in classic retail; do
    run "load/$mode" env CHATIFY_STUB_MODE="$mode" lua5.1 tools/stub/load_test.lua
    run "mentions/$mode" env CHATIFY_STUB_MODE="$mode" lua5.1 tools/mention_probe.lua
    run "commands/$mode" env CHATIFY_STUB_MODE="$mode" lua5.1 tools/command_probe.lua
    run "proxy prototype/$mode" env CHATIFY_STUB_MODE="$mode" lua5.1 tools/proxy_probe.lua
done
run "copy" lua5.1 tools/copy_probe.lua
run "public hooks" lua5.1 tools/hook_probe.lua
run "SavedVariables serialization" lua5.1 tools/savedvars_test.lua
run "strict API capabilities" lua5.1 tools/strict_api_probe.lua
run "R1-01 atomic profile backups" lua5.1 tools/profile_integrity_probe.lua
run "R1-02 post-hook lifecycle" lua5.1 tools/frame_hook_lifecycle_probe.lua
run "R1-04 history/render/buffer parity" lua5.1 tools/history_pipeline_probe.lua
run "R1-05/06 friend identity and Unicode keywords" lua5.1 tools/filter_identity_unicode_probe.lua
run "R1-07 PvP/BG/LFG queues and pending returns" lua5.1 tools/auto_reply_queue_probe.lua
# R2-04/05/06 viewport, inline hex/picker and keyboard search contracts.
for config in "retail modern" "forever modern" "era legacy" "tbc legacy" "mists modern" "titan modern"; do
    read -r client api <<< "$config"
    run "R2 responsive/colour/keyboard / $client" env CHATIFY_SETTINGS_CLIENT="$client" CHATIFY_SETTINGS_API="$api" lua5.1 tools/settings_responsive_probe.lua
done
run "R2 native editor/defaults / Retail" env CHATIFY_SETTINGS_CLIENT=retail CHATIFY_SETTINGS_API=modern lua5.1 tools/settings_edit_probe.lua
run "R2 native editor/defaults / Forever" env CHATIFY_SETTINGS_CLIENT=forever CHATIFY_SETTINGS_API=modern lua5.1 tools/settings_edit_probe.lua
run "R2 native editor/defaults / Era legacy" env CHATIFY_SETTINGS_CLIENT=era CHATIFY_SETTINGS_API=legacy lua5.1 tools/settings_edit_probe.lua
run "R2 native editor/defaults / TBC legacy" env CHATIFY_SETTINGS_CLIENT=tbc CHATIFY_SETTINGS_API=legacy lua5.1 tools/settings_edit_probe.lua
run "R2 native editor/defaults / Mists" env CHATIFY_SETTINGS_CLIENT=mists CHATIFY_SETTINGS_API=modern lua5.1 tools/settings_edit_probe.lua

clients=$(lua5.1 tools/stub/client_fixtures.lua) || { echo 'FAIL: fixture generation' >&2; exit 1; }
if [ -z "$clients" ]; then echo 'FAIL: fixture list is empty' >&2; exit 1; fi
for client in $clients; do
    run "identity/$client" env CHATIFY_COMPAT_CLIENT="$client" lua5.1 tools/compatibility_probe.lua
    for view in standalone embedded; do
        if [ "$client" = "plunderstorm" ]; then
            # Experimental fixture intentionally has no channel API. Not a pass.
            echo "OPTIONAL SKIP labels/plunderstorm/$view: API deliberately absent in synthetic fixture"
            optional_skips=$((optional_skips+1))
        else
            run "labels/$client/$view" env CHATIFY_LABEL_CLIENT="$client" CHATIFY_LABEL_VIEW="$view" lua5.1 tools/channel_label_probe.lua
        fi
    done
    for api in modern legacy late; do
        run "settings/$client/$api" env CHATIFY_SETTINGS_CLIENT="$client" CHATIFY_SETTINGS_API="$api" lua5.1 tools/settings_probe.lua
    done
done

printf '\nPASS: %d required checks; OPTIONAL SKIP: %d (documented experimental fixture).\n' "$passed" "$optional_skips"
printf 'NOT RUN IN SOURCE GATE: real AceDB persistence, packaged libs, live-client taint. See R1-08.\n'
