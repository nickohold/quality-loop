#!/usr/bin/env python3
"""Banned-pattern gate — greps the actual diff against the standing kill-list.

Bans live in config/bans.txt (falls back to bans.example.txt), one rule per line:
    <kind>::<regex>::<human message>
kind = added_comment | type_in_class | concept | dependency | generic
Only ADDED lines (diff '+') are checked, so pre-existing code is not flagged.
"""
import re, sys, qllib

def added_lines(diff):
    """Return list of (file, text) for added lines."""
    out = []
    cur = None
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
    rules = qllib.load_list("bans.txt")
    findings = []
    for rule in rules:
        parts = rule.split("::", 2)
        if len(parts) != 3:
            continue
        kind, rx, human = parts
        try:
            cre = re.compile(rx)
        except re.error:
            continue
        for f, text in adds:
            # type_in_class only applies to class/service-style files
            if kind == "type_in_class" and not re.search(r"\.(service|controller|module|class)\.[tj]s$", f):
                continue
            if cre.search(text):
                findings.append("BANNED [%s] in %s: \"%s\" — %s" % (kind, f, text.strip()[:80], human))
    # de-dup, cap
    seen, uniq = set(), []
    for x in findings:
        if x not in seen:
            seen.add(x); uniq.append(x)
    return uniq[:25]

if __name__ == "__main__":
    tp = sys.argv[1] if len(sys.argv) > 1 else ""
    cwd = sys.argv[2] if len(sys.argv) > 2 else "."
    for f in run(tp, cwd):
        print(f)
