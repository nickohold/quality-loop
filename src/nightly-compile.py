#!/usr/bin/env python3
"""Gather the last 24h of the operator's typed messages into a corpus file.

This is the cheap, programmatic HALF of the flywheel — it only collects the raw
material. The UNDERSTANDING is done by an LLM (`claude -p`) in nightly-compile.sh,
because friction is semantic: a keyword match can only find patterns someone
already thought to list, which is exactly what the flywheel exists to get past.

Prints the corpus path on stdout; a one-line summary on stderr.
"""
import os, glob, json, time, sys, qllib

PROJECTS = os.path.expanduser("~/.claude/projects/")
WINDOW = 24 * 3600

def text_of(c):
    if isinstance(c, str): return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return ""

def main():
    now = time.time()
    files = [f for f in glob.glob(PROJECTS + "**/*.jsonl", recursive=True)
             if "/subagents/" not in f and "statusline" not in f]
    rows = []
    for f in files:
        try:
            if now - os.path.getmtime(f) > WINDOW:
                continue
        except Exception:
            continue
        try:
            with open(f, errors="ignore") as fh:
                for line in fh:
                    try: o = json.loads(line)
                    except: continue
                    if o.get("type") != "user": continue
                    m = o.get("message")
                    if not isinstance(m, dict) or m.get("role") != "user": continue
                    if o.get("isSidechain"): continue
                    t = text_of(m.get("content")).strip()
                    if not t or t.startswith("<") or "[Request interrupted" in t[:40]:
                        continue
                    ts = o.get("timestamp", "")[:16]
                    repo = f.replace(PROJECTS, "").split("/")[0]
                    rows.append("===[%s|%s]===\n%s" % (ts, repo, t[:2000]))
        except Exception:
            continue

    state = os.path.join(qllib.QL_DIR, "state")
    os.makedirs(state, exist_ok=True)
    corpus = os.path.join(state, "nightly-corpus.txt")
    with open(corpus, "w") as w:
        w.write("\n\n".join(rows))
    sys.stderr.write("collected %d operator messages from the last 24h\n" % len(rows))
    print(corpus)

if __name__ == "__main__":
    main()
