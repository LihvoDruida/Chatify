#!/usr/bin/env python3
"""Static checks for two failure modes luac -p cannot see.

Both of these have actually shipped:

1. A call to ns.Something() where nothing ever assigns ns.Something. This is what
   produced "ChatVisuals.lua:960: attempt to call a nil value" in 0.11.29 - a
   slice-and-replace edit removed the hook-management functions while leaving
   their call sites behind. luac accepts it because it is a valid table index;
   it only fails when the line runs.

2. A local function called from a line above its own declaration. Lua resolves
   the name at compile time, so the earlier reference is not the local at all -
   it silently becomes a global lookup that yields nil. Again valid syntax,
   nil at runtime.

    python3 tools/check_symbols.py

Exits non-zero on any finding, so it can be wired into CI next to
generate_tocs.py --check.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUA_FILES = sorted(ROOT.glob("*.lua")) + sorted(ROOT.glob("locale/*.lua"))

# ns.Name = ... | function ns.Name( | ns.Name = function
DEFINE_NS = re.compile(r"""(?<![\w.])(?:function\s+ns\.([A-Za-z_]\w*)|ns\.([A-Za-z_]\w*)\s*=)""")
# The lookbehind matters: without it C_AddOns.IsAddOnLoaded() matches as
# "ns.IsAddOnLoaded()" and is reported as an undefined call.
CALL_NS = re.compile(r"(?<![\w.])ns\.([A-Za-z_]\w*)\s*\(")
# Any other mention: type(ns.Foo), pcall(ns.Foo, ...) - counts as a use, not a call.
REF_NS = re.compile(r"(?<![\w.])ns\.([A-Za-z_]\w*)")

DECL_LOCAL_FN = re.compile(r"^\s*local\s+function\s+([A-Za-z_]\w*)\s*\(")
DECL_LOCAL_VAR = re.compile(r"^\s*local\s+([A-Za-z_][\w\s,]*?)\s*=")
DECL_FORWARD = re.compile(r"^\s*local\s+([A-Za-z_][\w\s,]*?)\s*$")

# `local pcall = pcall` caches a global in an upvalue. Uses above that line
# resolve to the same global, so they are correct, not a bug.
DECL_SELF_CACHE = re.compile(r"^\s*local\s+([A-Za-z_]\w*)\s*=\s*\1\s*$")


def strip_comments(text):
    """Blank out long comments and line comments, preserving line numbering."""
    text = re.sub(r"--\[\[.*?\]\]", lambda m: "\n" * m.group(0).count("\n"),
                  text, flags=re.S)
    return "\n".join(re.sub(r"--.*$", "", line) for line in text.split("\n"))


def collect_ns_definitions():
    defined = set()
    for path in LUA_FILES:
        body = strip_comments(path.read_text(encoding="utf-8"))
        for m in DEFINE_NS.finditer(body):
            defined.add(m.group(1) or m.group(2))
    return defined


def check_ns_calls(defined):
    problems = []
    for path in LUA_FILES:
        body = strip_comments(path.read_text(encoding="utf-8"))
        for lineno, line in enumerate(body.split("\n"), 1):
            for m in CALL_NS.finditer(line):
                name = m.group(1)
                if name not in defined:
                    problems.append(
                        f"{path.name}:{lineno}: calls ns.{name}(), which is never assigned")
    return problems


def check_local_use_before_declaration():
    problems = []
    for path in LUA_FILES:
        body = strip_comments(path.read_text(encoding="utf-8"))
        lines = body.split("\n")

        # Only file-scope declarations matter here; an indented local is inside a
        # function and its uses are almost always in the same scope.
        declared = {}
        for lineno, line in enumerate(lines, 1):
            if DECL_SELF_CACHE.match(line):
                continue
            for pattern in (DECL_LOCAL_FN, DECL_LOCAL_VAR, DECL_FORWARD):
                m = pattern.match(line)
                if m:
                    for name in m.group(1).split(","):
                        name = name.strip()
                        if name and name.isidentifier():
                            declared.setdefault(name, lineno)
                    break

        for name, decl_line in declared.items():
            if len(name) < 3:
                continue
            call = re.compile(r"(?<![\w.:])" + re.escape(name) + r"\s*\(")
            for lineno, line in enumerate(lines, 1):
                if lineno >= decl_line:
                    break
                if call.search(line):
                    problems.append(
                        f"{path.name}:{lineno}: calls {name}(), declared as a local "
                        f"at line {decl_line} - this resolves to a nil global")
                    break
    return problems


def main():
    defined = collect_ns_definitions()
    problems = check_ns_calls(defined) + check_local_use_before_declaration()

    if problems:
        print("Symbol check failed:\n")
        for p in problems:
            print("  " + p)
        sys.exit(1)

    print(f"Symbol check passed ({len(defined)} ns.* functions, "
          f"{len(LUA_FILES)} files).")


if __name__ == "__main__":
    main()
