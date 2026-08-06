#!/usr/bin/env python3
"""Deeper static audit for failure modes that Lua accepts silently.

Every check here corresponds to something that compiles cleanly and either does
the wrong thing or errors only on the line that runs.

    A  duplicate keys in one table literal - the later one silently wins
    B  duplicate ns.* definitions - the later one silently wins
    C  profile fields read that no default declares - usually a typo, always nil
    D  AceEvent handlers named as strings with no matching method
    E  duplicate `order` values inside one AceConfig args table
    F  ns.* referenced (not just called) but never assigned

    python3 tools/audit.py [--strict]

Without --strict only certain findings are fatal; C and E are reported but not
failed on, since both have legitimate exceptions.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA = sorted(ROOT.glob("*.lua")) + sorted(ROOT.glob("locale/*.lua"))


def strip_comments(text):
    text = re.sub(r"--\[\[.*?\]\]", lambda m: "\n" * m.group(0).count("\n"),
                  text, flags=re.S)
    out = []
    for line in text.split("\n"):
        # Leave --  inside string literals alone by refusing to strip when the
        # marker sits after an odd number of unescaped quotes.
        idx = line.find("--")
        while idx != -1:
            before = line[:idx]
            if before.count('"') % 2 == 0 and before.count("'") % 2 == 0:
                line = before
                break
            idx = line.find("--", idx + 2)
        out.append(line)
    return "\n".join(out)


def table_blocks(lines):
    """Yield (start, end, indent) for each `{`-opened block, tracking depth."""
    stack = []
    for lineno, line in enumerate(lines, 1):
        for ch in line:
            if ch == "{":
                stack.append(lineno)
            elif ch == "}" and stack:
                yield stack.pop(), lineno
    while stack:
        yield stack.pop(), len(lines)


# --- A: duplicate keys in one table literal ------------------------------
KEY_ASSIGN = re.compile(r"^(\s*)([A-Za-z_]\w*)\s*=")
KEY_BRACKET = re.compile(r"""^(\s*)\[\s*(".*?"|'.*?'|\d+)\s*\]\s*=""")


def check_duplicate_table_keys():
    findings = []
    for path in LUA:
        lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
        # Group keys by (depth, indent) which approximates "same table literal".
        depth = 0
        seen = defaultdict(dict)
        for lineno, line in enumerate(lines, 1):
            m = KEY_ASSIGN.match(line) or KEY_BRACKET.match(line)
            # In Lua `{` only ever opens a table constructor, so depth > 0 means
            # we are inside one. The trailing comma requirement then separates a
            # real table entry from a plain assignment inside a function that
            # happens to be nested in a table.
            if m and depth > 0 and (line.rstrip().endswith(",")
                                    or line.rstrip().endswith("{")):
                indent = len(m.group(1))
                key = m.group(2)
                scope = (depth, indent)
                if key in seen[scope]:
                    findings.append(
                        f"{path.name}:{lineno}: duplicate key {key} in the same "
                        f"table (first at line {seen[scope][key]}) - the later "
                        f"one silently wins")
                else:
                    seen[scope][key] = lineno
            opened = line.count("{") - line.count("}")
            if opened != 0:
                # A change in depth ends the sibling scope at deeper indents.
                depth += opened
                for scope in list(seen):
                    if scope[0] > depth:
                        del seen[scope]
    return findings


# --- B: duplicate ns.* definitions ---------------------------------------
DEFINE_NS = re.compile(r"^\s*(?:function\s+ns\.([A-Za-z_]\w*)\s*\(|ns\.([A-Za-z_]\w*)\s*=\s*function)")


def check_duplicate_ns_definitions():
    seen, findings = {}, []
    for path in LUA:
        lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
        for lineno, line in enumerate(lines, 1):
            m = DEFINE_NS.match(line)
            if m:
                name = m.group(1) or m.group(2)
                where = f"{path.name}:{lineno}"
                if name in seen:
                    findings.append(
                        f"{where}: ns.{name} redefined (first at {seen[name]}) "
                        f"- the later definition silently wins")
                else:
                    seen[name] = where
    return findings


# --- C: profile fields with no default -----------------------------------
# Only the unambiguous spelling. A bare `db.` also matches the char-scoped
# database and other addons' tables (ElvUI's CH.db), which produced nothing
# but false positives.
PROFILE_READ = re.compile(r"self\.db\.profile\.([A-Za-z_]\w*)")


def collect_defaults():
    body = strip_comments((ROOT / "Config.lua").read_text(encoding="utf-8"))
    # The defaults live in one profile = { ... } block.
    m = re.search(r"profile\s*=\s*\{", body)
    if not m:
        return set()
    start = m.end() - 1
    depth, i = 0, start
    while i < len(body):
        if body[i] == "{":
            depth += 1
        elif body[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    block = body[start:i]
    keys = set(re.findall(r"^\s*([A-Za-z_]\w*)\s*=", block, re.M))
    keys |= set(re.findall(r"^\s*\[\"([^\"]+)\"\]\s*=", block, re.M))
    return keys


# Fields that legitimately have no default: nested tables, runtime scratch, and
# names that also exist as locals or on unrelated tables.
PROFILE_IGNORE = {
    "profile", "global", "char", "realm", "class", "faction", "race",
    "sounds", "events", "enable", "name", "key", "id", "text", "value",
    "type", "order", "args", "get", "set", "func", "desc", "width",
    # Intentional legacy key, read only to migrate away from it.
    "retailDisableChatFilters",
}


def check_profile_fields(defaults):
    findings = []
    for path in LUA:
        if path.name in ("Config.lua",):
            continue
        lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
        for lineno, line in enumerate(lines, 1):
            for m in PROFILE_READ.finditer(line):
                field = m.group(1)
                if field in PROFILE_IGNORE or field in defaults:
                    continue
                if field[0].isupper():
                    continue  # method call on some other table
                findings.append(
                    f"{path.name}:{lineno}: profile field '{field}' has no entry "
                    f"in the Config.lua defaults")
    return findings


# --- D: AceEvent string handlers with no method --------------------------
REG_EVENT = re.compile(r"""Register(?:Event|Message)\w*\(\s*(?:self\s*,\s*)?["'][A-Z_]+["']\s*,\s*["']([A-Za-z_]\w*)["']""")


def check_event_handlers():
    findings = []
    for path in LUA:
        body = strip_comments(path.read_text(encoding="utf-8"))
        methods = set(re.findall(r"function\s+\w+[:.]([A-Za-z_]\w*)\s*\(", body))
        for lineno, line in enumerate(body.split("\n"), 1):
            for m in REG_EVENT.finditer(line):
                handler = m.group(1)
                if handler not in methods:
                    findings.append(
                        f"{path.name}:{lineno}: registers handler '{handler}', "
                        f"which is not defined as a method in this file")
    return findings


# --- E: duplicate order values in one AceConfig args table ---------------
def check_option_orders():
    findings = []
    for path in LUA:
        if path.name != "Settings.lua":
            continue
        lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
        depth = 0
        orders = defaultdict(dict)
        for lineno, line in enumerate(lines, 1):
            m = re.match(r"^(\s*)order\s*=\s*([0-9.]+)\s*,", line)
            if m:
                indent, value = len(m.group(1)), m.group(2)
                scope = (depth, indent)
                if value in orders[scope]:
                    findings.append(
                        f"{path.name}:{lineno}: order {value} already used at "
                        f"line {orders[scope][value]} in the same options group "
                        f"- their on-screen order is undefined")
                else:
                    orders[scope][value] = lineno
            change = line.count("{") - line.count("}")
            if change:
                depth += change
                for scope in list(orders):
                    if scope[0] > depth:
                        del orders[scope]
    return findings


# --- F: ns.* referenced but never assigned -------------------------------
ANY_DEFINE_NS = re.compile(r"(?<![\w.])(?:function\s+ns\.([A-Za-z_]\w*)|ns\.([A-Za-z_]\w*)\s*=)")
# The lookbehind matters: without it C_AddOns.IsAddOnLoaded matches as
# "ns.IsAddOnLoaded", and every such call is reported as undefined.
REF_NS = re.compile(r"(?<![\w.])ns\.([A-Za-z_]\w*)")


def check_ns_references():
    defined = set()
    for path in LUA:
        body = strip_comments(path.read_text(encoding="utf-8"))
        for m in ANY_DEFINE_NS.finditer(body):
            defined.add(m.group(1) or m.group(2))

    findings = []
    for path in LUA:
        lines = strip_comments(path.read_text(encoding="utf-8")).split("\n")
        for lineno, line in enumerate(lines, 1):
            for m in REF_NS.finditer(line):
                name = m.group(1)
                if name not in defined:
                    findings.append(
                        f"{path.name}:{lineno}: ns.{name} is referenced but "
                        f"never assigned anywhere")
    return findings


def main():
    strict = "--strict" in sys.argv
    defaults = collect_defaults()

    fatal = {
        "duplicate table keys": check_duplicate_table_keys(),
        "duplicate ns.* definitions": check_duplicate_ns_definitions(),
        "missing event handlers": check_event_handlers(),
        "undefined ns.* references": check_ns_references(),
    }
    advisory = {
        "profile fields with no default": check_profile_fields(defaults),
        "duplicate option orders": check_option_orders(),
    }

    failed = False
    for title, items in fatal.items():
        if items:
            failed = True
            print(f"\n{title.upper()} ({len(items)}):")
            for i in items:
                print("  " + i)

    for title, items in advisory.items():
        if items:
            print(f"\n[advisory] {title} ({len(items)}):")
            for i in items:
                print("  " + i)
            if strict:
                failed = True

    if not failed and not any(advisory.values()):
        print(f"Audit clean ({len(defaults)} profile defaults, {len(LUA)} files).")
    elif not failed:
        print("\nNo fatal findings.")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
