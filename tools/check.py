#!/usr/bin/env python3
"""Structure check for OpenComputers Lua files in this repo.

Verifies block balance (function/if/do/repeat vs end/until) with
comment- and string-stripping, per file. Not a real parser -- a fast
tripwire for truncation and unbalanced edits, since the code can only
truly run inside Minecraft.

A full run also checks beefiles.txt, the list beeupdate installs
from: a module that is not listed there never reaches the in-game
computer, and nothing else would catch that.

Usage: python3 tools/check.py [files...]   (default: all *.lua)
Exit code 1 on any failure.
"""
import os
import re
import sys
import glob

MANIFEST = "beefiles.txt"
# Installed by hand on the ROBOT's filesystem, not the PC's.
EXCLUDED = {"beebot.lua"}

def check(path):
    depth, bad = 0, False
    lines = open(path, encoding="utf-8").readlines()
    for n, line in enumerate(lines, 1):
        code = re.sub(r"--.*", "", line)
        code = re.sub(r'"([^"\\]|\\.)*"', '""', code)
        code = re.sub(r"'([^'\\]|\\.)*'", "''", code)
        for tok in re.findall(r"\b(function|if|do|repeat|until|end)\b", code):
            depth += 1 if tok in ("function", "if", "do", "repeat") else -1
            if depth < 0:
                print(f"{path}: UNDERFLOW at line {n}: {line.strip()}")
                bad = True
    ok = depth == 0 and not bad
    status = "OK" if ok else f"DEPTH {depth}"
    print(f"{path:24} {status:8} {len(lines):4} lines"
          + ("  (over 200 -- consider splitting)" if len(lines) > 200 else ""))
    return ok

def check_manifest(path=MANIFEST):
    """Every .lua is listed in beefiles.txt or deliberately excluded,
    and every source it lists actually exists."""
    if not os.path.exists(path):
        print(f"{path}: MISSING -- beeupdate has nothing to read")
        return False
    listed, ok = {}, True
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2 or not parts[1].startswith("/"):
            print(f"{path}: line {n} is not '<source> <path> [keep]': {line}")
            ok = False
            continue
        listed[parts[0]] = parts[1]
    for src in sorted(listed):
        if not os.path.exists(src):
            print(f"{path}: lists {src}, which is not in the repo")
            ok = False
    for f in sorted(glob.glob("*.lua")):
        if f not in listed and f not in EXCLUDED:
            print(f"{path}: does not list {f} -- beeupdate won't install it")
            ok = False
    status = "OK" if ok else "DRIFT"
    print(f"{path:24} {status:8} {len(listed):4} entries")
    return ok

def main():
    files = sys.argv[1:] or sorted(glob.glob("**/*.lua", recursive=True))
    if not files:
        print("no .lua files found")
        return 0
    ok = all([check(f) for f in files])
    # Only on a full run: a targeted check shouldn't demand a manifest
    if not sys.argv[1:]:
        ok = check_manifest() and ok
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())