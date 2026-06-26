#!/usr/bin/env python3
"""Bans gate: grep ADDED diff lines against config/bans.txt (kind::regex::message)."""
import re, sys, qllib

def added_lines(diff):
    out, cur = [], None
    for ln in diff.splitlines():
        if ln.startswith("+++ b/"):
            cur = ln[6:]
        elif ln.startswith("+") and not ln.startswith("+++"):
            out.append((cur or "?", ln[1:]))
    return out

def run(transcript_path, cwd):
    diff = qllib.git_diff(cwd)
    if not diff.strip():
        return []
    adds = added_lines(diff)
    findings = []
    for rule in qllib.load_list("bans.txt"):
        parts = rule.split("::", 2)
        if len(parts) != 3:
            continue
        kind, rx, human = parts
        try:
            cre = re.compile(rx)
        except re.error:
            continue
        for f, text in adds:
            if kind == "type_in_class" and not re.search(r"\.(service|controller|module|class)\.[tj]s$", f):
                continue
            if cre.search(text):
                findings.append("BANNED [%s] in %s: \"%s\" — %s" % (kind, f, text.strip()[:80], human))
    seen, uniq = set(), []
    for x in findings:
        if x not in seen:
            seen.add(x); uniq.append(x)
    return uniq[:25]

if __name__ == "__main__":
    for f in run(sys.argv[1] if len(sys.argv) > 1 else "", sys.argv[2] if len(sys.argv) > 2 else "."):
        print(f)
