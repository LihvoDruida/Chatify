#!/usr/bin/env python3
"""Generate the per-flavour .toc files from Chatify.toc.

Chatify.toc is the single source of truth: it holds the Mainline (Retail) build
and the authoritative file list, version, and metadata. Every other .toc is
produced from it by swapping three headers - Interface, X-Flavor and
X-Expansion - and nothing else.

This exists because the previous hand-maintained flavour files drifted: they sat
at 0.11.15 while Chatify.toc had moved on to 0.11.21, and they used the dash
naming (Chatify-Wrath.toc) which the client does not load at all. Run this after
every version bump.

    python3 tools/generate_tocs.py          # write the files
    python3 tools/generate_tocs.py --check  # verify they are current (CI)

Naming: the client looks for AddonName_<Flavour>.toc first and falls back to
AddonName.toc when none matches. The suffix is separated by an UNDERSCORE. The
older dash forms are only recognised for a handful of legacy names, which is why
Chatify-Wrath.toc never loaded on any client.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Chatify.toc"

# suffix -> (Interface, X-Flavor, X-Expansion, live?)
#
# "live" records whether the client is currently reachable. Keep these current:
# an interface number one patch behind is exactly what gets the addon flagged
# out of date, which is what users report. TBC is live again as the Burning
# Crusade Classic Anniversary realms (2.5.6 -> 20506).
FLAVOURS = {
    "Vanilla": ("11508", "classic", "Vanilla", True),
    "TBC":     ("20506", "classic", "TBC", True),
    "Wrath":   ("30405", "classic", "Wrath", False),
    "Cata":    ("40402", "classic", "Cata", False),
    "Mists":   ("50504", "classic", "Mists", True),
}

HEADER_ORDER = ("## Interface:", "## X-Flavor:", "## X-Expansion:")


def read_source():
    if not SOURCE.exists():
        sys.exit("Chatify.toc not found - run this from the addon root.")
    return SOURCE.read_text(encoding="utf-8-sig").splitlines()


def build(lines, interface, flavour, expansion, suffix):
    out = []
    for line in lines:
        if line.startswith("## Interface:"):
            out.append("## Interface: " + interface)
        elif line.startswith("## X-Flavor:"):
            out.append("## X-Flavor: " + flavour)
        elif line.startswith("## X-Expansion:"):
            out.append("## X-Expansion: " + expansion)
        else:
            out.append(line)

    missing = [h for h in HEADER_ORDER if not any(l.startswith(h) for l in out)]
    if missing:
        sys.exit("Chatify.toc is missing required headers: " + ", ".join(missing))

    banner = [
        "# GENERATED FILE - do not edit.",
        "# Produced from Chatify.toc by tools/generate_tocs.py.",
        "# Edit Chatify.toc and re-run the script instead.",
        "",
    ]
    return "\n".join(banner + out).rstrip() + "\n"


def main():
    check = "--check" in sys.argv
    lines = read_source()

    version = next((l.split(":", 1)[1].strip() for l in lines
                    if l.startswith("## Version:")), "?")

    stale = []
    for suffix, (interface, flavour, expansion, _live) in FLAVOURS.items():
        target = ROOT / f"Chatify_{suffix}.toc"
        content = build(lines, interface, flavour, expansion, suffix)

        if check:
            current = target.read_text(encoding="utf-8") if target.exists() else ""
            if current != content:
                stale.append(target.name)
        else:
            target.write_text(content, encoding="utf-8")
            print(f"wrote {target.name}  (Interface {interface}, version {version})")

    if check:
        if stale:
            sys.exit("Out of date, re-run tools/generate_tocs.py: " + ", ".join(stale))
        print(f"All flavour .toc files are current (version {version}).")


if __name__ == "__main__":
    main()
