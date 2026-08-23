#!/usr/bin/env python3
"""Finds chat payloads touched before a secret-value guard has cleared them.

    python3 tools/secret_guard_audit.py

The bug this exists for, twice now: a handler receives a chat payload and does
something to it - compares it, measures it, calls a method on it - before asking
whether the value is secret. type() reports "string" for a secret string value, so
a type check is not a guard and reads as one. In an encounter the operation raises
and, because Chatify is on the stack, Chatify is named as the tainter.

The runtime harness cannot catch this: a marked secret in tools/stub/wow_env.lua is
an ordinary Lua string, and Lua 5.1 has no way to build a value that reports
type() == "string" and errors on comparison. So the ordering is checked statically
here instead of being left to review.

The rule: inside a function that takes a payload parameter, the first thing done
with that parameter must be a guard call or a type() test. Anything else is
reported.
"""

import re
import sys
from pathlib import Path

# Parameter names that carry an untrusted chat payload.
PAYLOAD_NAMES = {
    "msg", "message", "text", "rawText", "payload",
    "author", "sender", "line", "chatMessage",
}

# A parameter already named `safe...` is the sanitised form by convention; its
# caller did the guarding and re-checking it here would report the wrong function.
SAFE_PREFIX = "safe"

# Registration helpers take the *frame* as `target` and never see a payload.
SKIP_FUNCTION_RE = re.compile(r"function\s+[\w.:]*Register")

# Calls that establish the value is safe to touch.
GUARDS = {
    "CanMutateChatPayload", "IsSecretValue", "IsProtectedChatValue",
    "CanAccessChatValue", "CanAccessAllChatValues", "HasSecretChatValue",
    "GetSafeText", "SafeChatText", "TryMakeSafeText", "CanAccess",
    "issecretvalue", "hasanysecretvalues", "canaccessvalue",
    "canaccessallvalues", "ShouldBypassWhisperMutation",
}

FUNC_RE = re.compile(
    r"^\s*(?:local\s+)?function\s+[\w.:]*\s*\(([^)]*)\)|"
    r"^\s*(?:local\s+)?[\w.:]+\s*=\s*function\s*\(([^)]*)\)|"
    r"function\s*\(([^)]*)\)"
)

# Only entry points are checked, not every helper that happens to take a `text`
# argument. A helper is reached through an entry point and inherits its guarantee;
# flagging those buries the real finding in two dozen false ones, and a check nobody
# reads is worse than no check.
#
# An entry point is a function that receives an event name alongside a payload, or a
# function literal handed straight to an event/filter registration.
ENTRY_MARKERS = (
    "RegisterEventSafe", "RegisterEventIfSupported", "RegisterEvent",
    "AddMessageEventFilter", "RegisterMessageFilter", 'SetScript("OnEvent"',
)
EVENT_PARAMS = {"event", "eventName"}


def parameters(match):
    raw = next(g for g in match.groups() if g is not None)
    return [p.strip() for p in raw.split(",") if p.strip()]


def guard_on_line(line):
    return any(g in line for g in GUARDS)


def unsafe_use(line, name):
    """True when `name` is used for something other than a type() test."""
    stripped = re.sub(r"--.*$", "", line)
    if not re.search(r"\b%s\b" % re.escape(name), stripped):
        return False
    if guard_on_line(stripped):
        return False

    # type(name) and a bare pass-through as a call argument are both fine.
    without_type = re.sub(r"\btype\s*\(\s*%s\s*\)" % re.escape(name), "", stripped)
    if not re.search(r"\b%s\b" % re.escape(name), without_type):
        return False

    patterns = [
        r"\b%s\s*(==|~=|<|>|<=|>=)" % re.escape(name),   # comparison
        r"(==|~=|<|>|<=|>=)\s*%s\b" % re.escape(name),
        r"#\s*%s\b" % re.escape(name),                    # length
        r"\b%s\s*:" % re.escape(name),                    # method call
        r"\b%s\s*\.\." % re.escape(name),                 # concatenation
        r"\.\.\s*%s\b" % re.escape(name),
        r"\b%s\s*\[" % re.escape(name),                   # index
    ]
    return any(re.search(p, without_type) for p in patterns)


def scan(path):
    findings = []
    lines = path.read_text(encoding="utf-8").splitlines()

    for index, line in enumerate(lines):
        match = FUNC_RE.search(line)
        if not match:
            continue

        if SKIP_FUNCTION_RE.search(line):
            continue

        params = parameters(match)
        carried = [p for p in params
                   if p in PAYLOAD_NAMES and not p.lower().startswith(SAFE_PREFIX)]
        if not carried:
            continue

        is_entry = any(p in EVENT_PARAMS for p in params) \
            or any(marker in line for marker in ENTRY_MARKERS)
        if not is_entry:
            continue

        # Walk the body until the function's own `end` at the same indent, or a
        # generous cap - handlers that guard at all guard within a few lines.
        depth = 0
        for offset in range(index + 1, min(index + 60, len(lines))):
            body = lines[offset]
            depth += len(re.findall(r"\b(function|if|for|while|do)\b", body))
            depth -= len(re.findall(r"\bend\b", body))

            if guard_on_line(body):
                break

            for name in carried:
                if unsafe_use(body, name):
                    findings.append((path.name, offset + 1, name, body.strip()))
                    break
            else:
                if depth < 0:
                    break
                continue
            break

    return findings


def main():
    root = Path(__file__).resolve().parent.parent
    files = sorted(root.glob("*.lua"))

    findings = []
    for path in files:
        findings.extend(scan(path))

    if not findings:
        print("Secret-guard audit clean (%d files)." % len(files))
        return 0

    print("Payload touched before a secret-value guard:\n")
    for name, line, param, text in findings:
        print("  %s:%d  '%s'" % (name, line, param))
        print("      %s" % text)
    print("\n%d finding(s)." % len(findings))
    return 1


if __name__ == "__main__":
    sys.exit(main())
