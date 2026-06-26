#!/usr/bin/env python3
"""Decide if a shell command actually INVOKES git merge / push-to-main / gh pr merge.
Parses the leading subcommand of each segment instead of substring-matching the whole string."""
import re, sys


def segments(cmd):
    return re.split(r"&&|\|\||[;|\n]", cmd)


def is_merge(cmd):
    for seg in segments(cmd):
        toks = seg.strip().split()
        while toks and ("=" in toks[0] or toks[0] in ("sudo", "command", "exec", "time", "nice", "env")):
            toks = toks[1:]
        if len(toks) < 2:
            continue
        prog, sub = toks[0], toks[1]
        args = toks[2:]
        if prog == "git":
            if sub == "merge" and not (args and args[0].startswith("-")):
                return True
            if sub == "push":
                if any(a in ("--force", "-f", "--force-with-lease") for a in args):
                    return True
                if any(a in ("main", "master") for a in args):
                    return True
        elif prog == "gh" and sub == "pr" and "merge" in args:
            return True
    return False


if __name__ == "__main__":
    sys.exit(0 if is_merge(sys.argv[1] if len(sys.argv) > 1 else "") else 1)
